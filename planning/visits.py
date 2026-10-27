"""Real-address visits with separately labeled retailer snapshots and historical evidence.

HTTP orchestration only; quote policy/ranking and scheduling are implemented in Jac.
"""
import jaclang
import hashlib
import json
import math
import re
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from urllib.parse import urlencode
from app_settings import instant, stamp
from integrations.providers import route, ProviderError, distance_m, store_details
from integrations.retail import quotes_for
from planning.comparisons import extend_plans, refresh_comparison
from planning.multistore import comparison_kind
from planning.retail import apply_quotes, visit_rank, quote_changes
import copy
from planning.schedule import schedule_visit
from planning.transit import bus_visit
from integrations.openprices import nearby_with_history, recommendation_records, CATEGORY_TAGS
from ai.matching import satisfies_requested_spec

ALIASES = {"yoghurt": "yogurt", "egg": "eggs"}
SUPPORTED = {"WALK", "BIKE", "CAR", "BUS"}
DISCLAIMER = "Historical observations only. Today's prices, stock and opening hours are unverified. Confirm package size, diet requirements and prices before buying."


def signature(context):
    return hashlib.sha256(json.dumps(context, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def words(value):
    return set(re.findall(r"[a-z0-9]+", str(value).casefold()))


def match_record(need, record, dietary, now):
    query = ALIASES.get(need["type"], need["type"]).casefold()
    name = str(record.get("name", "")).casefold()
    terms = words(query)
    tagged = CATEGORY_TAGS.get(query) in record.get("categories", [])
    if not terms or (not terms.issubset(words(name)) and not tagged):
        return False
    # Avoid common ingredient/derivative false positives for staple requests.
    exclusions = {"milk": {"chocolate", "powder", "soap", "tea", "coconut", "almond", "soy", "soya", "oat", "oats", "cashew", "rice", "condensed", "evaporated"}, "rice": {"cake", "cakes", "cracker", "crackers", "noodles", "cereal"}, "eggs": {"chocolate"}}
    if words(name) & exclusions.get(query, set()):
        return False
    if not satisfies_requested_spec(need, record.get("brand", ""), record.get("size_label", "")):
        return False
    labels = {str(x).removeprefix("en:") for x in record.get("labels", [])}
    if any(tag.removeprefix("en:") not in labels for tag in dietary):
        return False
    try:
        return date.fromisoformat(record["recorded_on"]) <= instant(now).date()
    except (ValueError, TypeError, KeyError):
        return False


def evidence_for(store, needs, dietary, now):
    if store.get("source") != "openprices":
        return {"records": [], "checked": 0, "partial": True, "notice": "Location only: no linked Open Prices evidence."}
    try:
        return recommendation_records(store["external_id"], [ALIASES.get(n["type"], n["type"]) for n in needs])
    except ProviderError as error:
        return {"records": [], "checked": 0, "partial": True, "notice": "Historical lookup unavailable: " + str(error)}


def route_for(origin, store, profile, now):
    candidates, errors = [], []
    for mode in profile["transport"]:
        if mode not in SUPPORTED:
            errors.append(mode + ": no verified public-transit/rideshare estimate available.")
            continue
        try:
            if mode == "BUS":
                candidates.append(bus_visit(origin, store, profile, now))
                continue
            travel = route([origin["lat"], origin["lon"]], [store["lat"], store["lon"]], mode)
            if not travel.get("valid_until") or instant(travel["valid_until"]) < instant(now):
                raise ProviderError("Route estimate expired; retry the search.")
            violations = []
            if mode == "WALK" and travel["walk_min"] > profile["max_walk_min"]:
                violations.append("Walking segment exceeds your walking limit.")
            total = int(travel["min"]) + 20
            schedule = schedule_visit(profile["free_windows"], travel, store, now, origin.get("timezone", ""))
            if schedule["blocker"]:
                violations.append(schedule["blocker"])
            candidates.append({**travel, "mode": mode, "total_min": total, "shopping_min": 20,
                               **schedule, "violations": violations})
        except ProviderError as error:
            errors.append(mode + ": " + str(error))
    if not candidates:
        return None, errors
    chosen = min(candidates, key=lambda x: (bool(x["violations"]), x["total_min"]))
    return chosen, errors


def candidate(store, evidence, context, now):
    needs, profile = context["needs"], context["profile"]
    items, matched, subtotal, priced, known_mass, weighed = [], 0, 0.0, 0, 0.0, 0
    for need in needs:
        matches = [row for row in evidence["records"] if str(row.get("location_id")) == str(store.get("external_id")) and match_record(need, row, profile["dietary"], now)]
        matches.sort(key=lambda x: (x["recorded_on"], x["record_id"]), reverse=True)
        record = matches[0] if matches else None
        item = {"category": need["type"], "qty": need["qty"], "outcome": "PENDING", "evidence": record,
                "reference_amount": None, "match_note": "No matching evidence in the checked records; check at the store."}
        if record:
            matched += 1
            item["match_note"] = "Name/spec matches a historical record; product suitability and stock still require your confirmation."
            # A per-kg/per-L record cannot be multiplied by a package count.
            price = record.get("price")
            if record.get("price_per") == "UNIT" and record.get("currency") == "USD" and not record.get("discounted") and type(price) in (int, float) and math.isfinite(price) and price >= 0:
                item["reference_amount"] = round(price * need["qty"], 2)
                subtotal += item["reference_amount"]
                priced += 1
            weight = record.get("weight_kg")
            if type(weight) in (int, float) and math.isfinite(weight) and weight > 0:
                known_mass += weight * need["qty"]
                weighed += 1
        items.append(item)
    travel, route_errors = route_for(context["origin"], store, profile, now)
    blockers = list(travel["violations"]) if travel else ["No supported route could be verified."]
    if known_mass > profile["carry_limit_kg"]:
        blockers.append("Known net product mass already exceeds your carrying limit.")
    subtotal = round(subtotal, 2)
    warnings = [DISCLAIMER]
    if store.get("details_notice"): warnings.append(store["details_notice"])
    if travel:
        if travel["timezone_notice"]: warnings.append(travel["timezone_notice"])
        if travel["hours_status"] == "REGULAR_HOURS_FIT":
            warnings.append("The suggested visit fits recorded regular opening hours. Holiday exceptions and unexpected closures still need checking.")
        else:
            warnings.append("Opening hours are missing, unsupported or do not fit your available time. Check the store before travelling.")
        warnings.append(travel["notice"] if travel["mode"] == "BUS" else "Future travel uses a current route estimate, not a traffic forecast. Refresh before departure.")
    if matched < len(needs): warnings.append(f"{len(needs)-matched} shopping need(s) have no matching evidence in the checked records.")
    if evidence.get("partial"): warnings.append("Historical search coverage is partial; unmatched does not mean unavailable.")
    if priced < len(needs): warnings.append("Reference subtotal excludes missing, discounted, non-USD and non-package prices.")
    if profile["weekly_budget"] <= 0:
        warnings.append("Set a budget to compare against the historical reference subtotal.")
    elif subtotal > profile["weekly_budget"]:
        warnings.append("Even the partial historical reference subtotal exceeds your saved budget.")
    warnings.append("Current budget feasibility is unknown; reference amounts exclude tax, fees and transport.")
    if weighed < len(needs): warnings.append("Full carrying weight is unknown; available net weights exclude packaging.")
    if travel and travel["mode"] == "CAR" and profile["transport_cost"] < 0:
        warnings.append("Driving cost is unknown; enter an estimate in your profile.")
    if evidence.get("notice"): warnings.append(evidence["notice"])
    nav_mode = {"WALK":"walking", "BIKE":"bicycling", "CAR":"driving", "BUS":"transit"}.get(travel["mode"] if travel else "", "walking")
    navigation = "https://www.google.com/maps/dir/?" + urlencode({"api":1, "origin":f'{context["origin"]["lat"]},{context["origin"]["lon"]}', "destination":f'{store["lat"]},{store["lon"]}', "travelmode":nav_mode})
    reason = f'{store["name"]}: {matched}/{len(needs)} needs have matching historical evidence.'
    if travel: reason += f' Estimated {travel["min"]} minutes round trip by {travel["mode"]}, plus 20 minutes shopping.'
    reason += " Ranked by route/time eligibility, historical match coverage, then trip duration and distance; not by today's price."
    return {"key":str(uuid.uuid4()), "kind":"HISTORICAL_STORE_VISIT", "status":"PROPOSED", "created_at":stamp(now),
            "input_signature":signature(context), "origin_label":context["origin"].get("address", "Confirmed location"),
            "store":store, "items":items, "matched":matched, "need_count":len(needs), "route":travel,
            "reference_subtotal":subtotal if priced else None, "priced_needs":priced,
            "known_net_weight_kg":round(known_mass, 2) if weighed else None, "weight_complete":weighed == len(needs),
            "blockers":blockers, "warnings":warnings, "route_notices":route_errors, "accept_allowed":not blockers,
            "explanation":reason, "navigation_url":navigation, "checked_records":evidence["checked"]}


def recommend(context, now):
    started = time.monotonic()
    if not context.get("origin"):
        raise ValueError("Confirm your shopping address first.")
    if not context.get("needs"):
        raise ValueError("Save at least one active shopping need before recommending stores.")
    found = nearby_with_history(context["origin"]["lat"], context["origin"]["lon"], context["radius_m"], include_kroger=True)
    nearby = found["stores"]
    # Bound API work while retaining both history-backed and location-only options.
    retailer = [s for s in nearby if s.get("source") == "kroger" and s.get("product_access")][:3]
    history = [s for s in nearby if s.get("source") == "openprices"][:max(0, 4-len(retailer))]
    chosen = retailer + history
    for store in nearby:
        if len(chosen) >= 6: break
        if store.get("source") == "kroger" and store.get("product_access") and store["id"] not in {s["id"] for s in retailer}: continue
        if store["id"] not in {s["id"] for s in chosen}: chosen.append(store)
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
        if not travel: continue
        if travel['mode'] == 'BUS':
            # A timetable is fixed. Never slide a departure to a time when the
            # scheduled bus does not run after slow provider requests.
            if instant(travel['departure_at']) <= instant(ready) or instant(travel['valid_until']) <= instant(ready):
                plan['blockers'].append('Scheduled departure passed or transit evidence expired during lookup. Refresh recommendations.')
                travel['violations'] = list(plan['blockers'])
            plan['accept_allowed'] = not plan['blockers']
            plan['created_at'] = stamp(ready)
            continue
        previous = travel.get('blocker', '')
        schedule = schedule_visit(context['profile']['free_windows'], travel, plan['store'], ready, context['origin'].get('timezone', ''))
        plan['blockers'] = [b for b in plan['blockers'] if not previous or b != previous]
        travel['violations'] = [b for b in travel['violations'] if not previous or b != previous]
        travel.update(schedule)
        if schedule['blocker']:
            plan['blockers'].append(schedule['blocker'])
            travel['violations'].append(schedule['blocker'])
        if instant(travel['valid_until']) < instant(ready):
            plan['blockers'].append('Route estimate expired during lookup. Refresh recommendations.')
        plan['accept_allowed'] = not plan['blockers']
        plan['created_at'] = stamp(ready)
    plans.sort(key=visit_rank)
    if len([p for p in plans if p['kind']=='CURRENT_STORE_VISIT']) >= 2 or context.get('delivery_quotes'):
        plans, ready, compared = extend_plans(plans, context, ready)
    else:
        compared = len(plans)
        plans = plans[:3]
    notices = found["notices"] + [f"Checked {len(chosen)} of {len(nearby)} nearby stores; compared {compared} bounded single-store, two-store and entered-delivery options. This is a bounded search, not an exhaustive inventory comparison."]
    if not plans: notices.append("No nearby stores were returned. Try a larger radius or another confirmed address.")
    return {"plans":plans, "stores":nearby, "notices":notices, "checked_stores":len(chosen), "nearby_count":len(nearby), "generated_at":stamp(ready)}


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
    travel = updated['route']
    if not travel or instant(travel['valid_until']) <= instant(checked) or (travel.get('departure_at') and instant(travel['departure_at']) <= instant(checked)):
        updated['blockers'].append('Route expired or departure passed during price verification. Generate new recommendations.')
    updated['accept_allowed'] = not updated['blockers']
    return updated
