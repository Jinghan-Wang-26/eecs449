"""Real-address visits with separately labeled retailer snapshots and historical evidence.

Provider calls, concurrency and timing only. Matching, store choice, route
choice, proposal rules, quote policy/ranking and scheduling are in Jac
(`planning/visit_rules.jac`, `planning/retail.jac`, `planning/schedule.jac`).
"""
import jaclang  # Enable imports of the Jac rule modules below.
import copy
import math
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from app_settings import instant, stamp
from integrations.providers import route, ProviderError, store_details
from integrations.retail import quotes_for
from planning.comparisons import extend_plans, refresh_comparison
from planning.multistore import comparison_kind
from planning.retail import apply_quotes, visit_rank, quote_changes
from planning.schedule import schedule_visit
from planning.transit import bus_visit
from planning.visit_rules import (SUPPORTED, best_route, choose_stores, history_candidate, match_record,
                                  recheck_after_lookup, refreshed_route_blocker, road_candidate,
                                  search_notice, search_term, signature, unsupported_mode_notice)
from integrations.openprices import nearby_with_history, recommendation_records

__all__ = ['candidate', 'match_record', 'recommend', 'refresh_visit', 'signature']


def evidence_for(store, needs, dietary, now):
    if store.get("source") != "openprices":
        return {"records": [], "checked": 0, "partial": True, "notice": "Location only: no linked Open Prices evidence."}
    try:
        return recommendation_records(store["external_id"], [search_term(n["type"]) for n in needs])
    except ProviderError as error:
        return {"records": [], "checked": 0, "partial": True, "notice": "Historical lookup unavailable: " + str(error)}


def route_for(origin, store, profile, now):
    candidates, errors = [], []
    for mode in profile["transport"]:
        if mode not in SUPPORTED:
            errors.append(unsupported_mode_notice(mode))
            continue
        try:
            if mode == "BUS":
                candidates.append(bus_visit(origin, store, profile, now))
                continue
            travel = route([origin["lat"], origin["lon"]], [store["lat"], store["lon"]], mode)
            if not travel.get("valid_until") or instant(travel["valid_until"]) < instant(now):
                raise ProviderError("Route estimate expired; retry the search.")
            schedule = schedule_visit(profile["free_windows"], travel, store, now, origin.get("timezone", ""))
            candidates.append(road_candidate(mode, travel, schedule, profile))
        except ProviderError as error:
            errors.append(mode + ": " + str(error))
    return best_route(candidates), errors


def candidate(store, evidence, context, now):
    travel, route_errors = route_for(context["origin"], store, context["profile"], now)
    return history_candidate(store, evidence, travel, route_errors, context, now)


def recommend(context, now):
    started = time.monotonic()
    if not context.get("origin"):
        raise ValueError("Confirm your shopping address first.")
    if not context.get("needs"):
        raise ValueError("Save at least one active shopping need before recommending stores.")
    found = nearby_with_history(context["origin"]["lat"], context["origin"]["lon"], context["radius_m"], include_kroger=True)
    nearby = found["stores"]
    chosen = choose_stores(nearby)

    def build(store):
        try:
            store = store_details(store)
        except ProviderError as error:
            store = {**store, "details_notice": str(error)}
        evidence = evidence_for(store, context["needs"], context["profile"]["dietary"], now)
        plan = candidate(store, evidence, context, now)
        if store.get('source') == 'kroger' and store.get('product_access'):
            lookup = quotes_for(store, context['needs'])
            checked = (instant(now) + timedelta(seconds=math.ceil(time.monotonic()-started))).isoformat()
            plan = apply_quotes(plan, lookup, context, checked)
        return plan

    with ThreadPoolExecutor(max_workers=3) as pool:
        plans = list(pool.map(build, chosen))
    # Provider calls can take time. Schedule against completion, not the instant
    # the user clicked, without issuing the route/history requests again.
    ready = (instant(now) + timedelta(seconds=math.ceil(time.monotonic() - started))).isoformat()
    for plan in plans:
        travel = plan['route']
        schedule = None
        if travel and travel['mode'] != 'BUS':
            schedule = schedule_visit(context['profile']['free_windows'], travel, plan['store'], ready,
                                      context['origin'].get('timezone', ''))
        recheck_after_lookup(plan, schedule, ready)
    plans.sort(key=visit_rank)
    if len([p for p in plans if p['kind'] == 'CURRENT_STORE_VISIT']) >= 2 or context.get('delivery_quotes'):
        plans, ready, compared = extend_plans(plans, context, ready)
    else:
        compared = len(plans)
        plans = plans[:3]
    notices = found["notices"] + [search_notice(len(chosen), len(nearby), compared)]
    if not plans:
        notices.append("No nearby stores were returned. Try a larger radius or another confirmed address.")
    return {"plans": plans, "stores": nearby, "notices": notices, "checked_stores": len(chosen),
            "nearby_count": len(nearby), "generated_at": stamp(ready)}


def refresh_visit(plan, context, now):
    """Uncached recheck at the same store. Return data, never accept a plan here."""
    if comparison_kind(plan):
        return refresh_comparison(plan, context, now)
    started = time.monotonic()
    previous = {item['category']: item.get('quote') for item in plan['items']}
    lookup = quotes_for(plan['store'], context['needs'], previous=previous, refresh=True)
    checked = (instant(now) + timedelta(seconds=math.ceil(time.monotonic()-started))).isoformat()
    updated = apply_quotes(copy.deepcopy(plan), lookup, context, checked)
    updated['quote_changes'] = quote_changes(plan, updated)
    blocker = refreshed_route_blocker(updated['route'], checked)
    if blocker:
        updated['blockers'].append(blocker)
    updated['accept_allowed'] = not updated['blockers']
    return updated
