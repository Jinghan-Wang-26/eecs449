"""Persistent store visits with historical evidence or rechecked retailer snapshots."""
import from app_settings { due, instant, get_settings }
import from planning.visits { recommend, signature, refresh_visit }
import from planning.retail { fresh_quote }
import from planning.multistore { comparison_kind }
import from planning.delivery { save_delivery_quote, delivery_issues }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from models.graph { owned, items_of }
import from sync.engine { sync_events }
import from integrations.validation { purchase_result }
import from budget.ledger { add_expense }


def visit_context(p: UserProfile, now: str) -> dict {
    state = owned(p, ShoppingWorkspace);
    return {"origin": p.location, "radius_m": state.search_radius_m,
        "delivery_quotes": list(getattr(state,"delivery_quotes",[])),
        "needs": [dict(n.product_spec) for n in items_of(p) if n.plannable() and (n.snoozed_until == "" or due(n.snoozed_until, now))],
        "profile": {"transport": p.transport, "max_walk_min": p.max_walk_min, "max_transfers": p.max_transfers,
            "free_windows": p.free_windows, "weekly_budget": p.weekly_budget,
            "carry_limit_kg": p.carry_limit_kg, "dietary": p.dietary,
            "time_value_per_hour": p.time_value_per_hour, "transport_cost": p.transport_cost, "tax_rate": p.tax_rate, "memberships": p.memberships}};
}

def invalidate_visits(p: UserProfile, message: str) -> None {
    state = owned(p, ShoppingWorkspace);
    for plan in state.visit_plans {
        if plan["status"] == "PROPOSED" { plan["status"] = "CANCELLED"; }
        elif plan["status"] in ["ACCEPTED", "IN_PROGRESS"] {
            plan["status"] = "NEEDS_REVIEW";
            plan["review_reason"] = message;
        }
    }
    state.visit_plans = list(state.visit_plans);
}

def visit_view(p: UserProfile, now: str) -> list {
    state = owned(p, ShoppingWorkspace);
    if (p.data_mode or get_settings()["data_mode"]) != "live" { return []; }
    sig = signature(visit_context(p, now));
    for plan in state.visit_plans {
        if plan["status"] not in ["PROPOSED", "ACCEPTED", "IN_PROGRESS"] { continue; }
        changed = plan["input_signature"] != sig;
        # The caller's clock may be the request start, before HTTP queries finished.
        as_of = max(instant(now), instant(plan.get('quote_checked_at') or now)).isoformat();
        expired = plan["route"] is not None and not due(as_of, plan["route"]["valid_until"]);
        departed = plan["route"] is not None and bool(plan["route"].get("departure_at")) and due(plan["route"]["departure_at"], as_of);
        stale_quotes = (plan.get('kind') == 'CURRENT_STORE_VISIT' or comparison_kind(plan)) and any([not fresh_quote(item['quote'], as_of) for item in plan['items'] if item.get('quote')]);
        stale_delivery = bool(plan.get('delivery_quote')) and instant(plan['delivery_quote']['valid_until']) <= instant(as_of);
        plan['quotes_expired'] = stale_quotes or stale_delivery;
        if changed or expired or stale_quotes or stale_delivery or (departed and plan["status"] == "PROPOSED") {
            plan["status"] = "NEEDS_REVIEW";
            plan["accept_allowed"] = False;
            plan["review_reason"] = "Inputs changed, quotes or route evidence expired, or departure passed. Refresh prices if the route still fits; otherwise generate a new visit.";
        }
    }
    state.visit_plans = list(state.visit_plans);
    return [plan for plan in state.visit_plans if plan["status"] != "CANCELLED"];
}

def recommend_visits(p: UserProfile, now: str) -> str {
    if (p.data_mode or get_settings()["data_mode"]) != "live" { raise ValueError("Choose Real stores for address-based recommendations."); }
    state = owned(p, ShoppingWorkspace);
    result = recommend(visit_context(p, now), now);
    visit_view(p, now);
    retained = [plan for plan in state.visit_plans if plan.get("accepted_at") and plan["status"] != "CANCELLED"][-7:];
    proposals = list(result["plans"]);
    state.visit_plans = retained + proposals;
    state.nearby_stores = result["stores"];
    state.notices = result["notices"];
    state.visit_search = {"generated_at": result["generated_at"], "checked_stores": result["checked_stores"], "nearby_count": result["nearby_count"]};
    return f"Generated {len(proposals)} store-visit options. Review retailer snapshots or historical evidence, product matches and route limits before accepting.";
}

def visit_action(p: UserProfile, data: dict, now: str) -> str {
    if (p.data_mode or get_settings()["data_mode"]) != "live" { raise ValueError("Choose Real stores first."); }
    state = owned(p, ShoppingWorkspace);
    plans = visit_view(p, now);
    found = [plan for plan in plans if plan["key"] == data.get("key")];
    if len(found) != 1 { raise ValueError("Visit plan not found. Generate new recommendations."); }
    plan = found[0]; action = data.get("action");
    if action == "refresh" or (action == "accept" and (plan.get('kind') == 'CURRENT_STORE_VISIT' or comparison_kind(plan))) {
        if (plan.get('kind') != 'CURRENT_STORE_VISIT' and not comparison_kind(plan)) or plan.get('accepted_at') or plan['status'] not in ['PROPOSED', 'NEEDS_REVIEW'] { raise ValueError('Only unaccepted retailer visits can refresh prices.'); }
        if plan['input_signature'] != signature(visit_context(p, now)) { raise ValueError('Shopping inputs changed. Generate new recommendations.'); }
        if action == 'accept' {
            if data.get('acknowledge_unknowns') is not True { raise ValueError('Review product matches, prices and unknowns before accepting.'); }
            if data.get('quote_revision') != plan.get('quote_revision') { raise ValueError('The displayed quote changed. Reload and review the latest version.'); }
        }
        if action == 'accept' and plan.get('delivery_quote') and data.get('delivery_reconfirmed') is not True { raise ValueError('Reconfirm the merchant checkout quote, address, basket, fees and slot before accepting. This does not place an order.'); }
        updated = refresh_visit(plan, visit_context(p, now), now);
        # A refreshed quote has not been compared against the other options again.
        updated['comparison_labels'] = []; updated['savings_vs_single'] = None; updated['compared_options'] = 0;
        plan.update(updated);
        plan['status'] = 'PROPOSED' if plan['accept_allowed'] else 'NEEDS_REVIEW';
        plan['quotes_expired'] = False;
        state.visit_plans = list(state.visit_plans);
        if not plan['accept_allowed'] or plan['quote_changes'] or action == 'refresh' {
            plan['review_reason'] = 'Prices and availability were rechecked. ' + ' '.join(plan['quote_changes']);
            if not plan['accept_allowed'] { plan['review_reason'] += ' Resolve the listed blockers or recommend stores again for alternatives.'; }
            else { plan['review_reason'] += ' Review the updated selection and confirm again.'; }
            return plan['review_reason'];
        }
        plan['last_verified_at'] = plan['quote_checked_at'];
        plan.pop('review_reason', None);
    }
    if action == "accept" {
        if plan["status"] != "PROPOSED" or not plan["accept_allowed"] { raise ValueError("This visit needs new recommendations or corrected travel constraints."); }
        if data.get("acknowledge_unknowns") is not True { raise ValueError("Acknowledge that current prices, stock and opening hours need checking."); }
        if any([other["status"] in ["ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"] for other in plans if other["key"] != plan["key"] and other.get("accepted_at")]) {
            raise ValueError("Complete or cancel your existing visit before accepting another.");
        }
        plan["status"] = "ACCEPTED";
        plan["accepted_at"] = plan.get("last_verified_at") or now;
        for other in state.visit_plans {
            if other["key"] != plan["key"] and other["status"] == "PROPOSED" { other["status"] = "CANCELLED"; }
        }
    } elif action == "cancel" {
        if plan["status"] == "COMPLETED" { raise ValueError("A completed visit cannot be cancelled."); }
        plan["status"] = "CANCELLED";
    } elif action == "outcome" {
        if not plan.get("accepted_at") or plan["status"] not in ["ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW", "COMPLETED"] { raise ValueError("Accept a visit before recording outcomes."); }
        if plan["input_signature"] != signature(visit_context(p, now)) { raise ValueError("Your shopping needs or constraints changed. Rebuild the visit before applying outcomes."); }
        items = [item for item in plan["items"] if item["category"] == data.get("category")];
        if len(items) != 1 { raise ValueError("Item is not in this visit."); }
        item = items[0]; result = purchase_result(data, item); outcome = result["outcome"];
        if item["outcome"] != "PENDING" {
            if item["outcome"] == outcome and item.get("bought_qty", result["bought_qty"]) == result["bought_qty"] and item.get("actual_paid") == result["actual_paid"] { return "Outcome already recorded."; }
            raise ValueError("This item already has an outcome.");
        }
        if outcome == "PARTIAL" {
            needs = [n for n in items_of(p) if n.plannable() and n.product_spec.get("type") == item["category"]];
            if len(needs) != 1 or needs[0].product_spec["qty"] != item["qty"] { raise ValueError("The requested quantity changed. Rebuild this visit."); }
            spec = dict(needs[0].product_spec);
            spec["qty"] = result["remaining_qty"];
            needs[0].product_spec = spec;
        }
        if outcome == "PURCHASED" {
            sync_events(p, [{"id": f"visit:{plan['key']}:{item['category']}",
                "type": "feedback", "target": item["category"], "reason": "PURCHASED"}], now, {"data_mode": "live"});
        }
        item.update(result);
        if result["actual_paid"] is not None and result["actual_paid"] > 0 {
            add_expense(p, {"id": f"visit:{plan['key']}:{item['category']}", "amount": result["actual_paid"],
                "store": item.get("store_name") or plan["store"]["name"], "category": item["category"],
                "spent_at": now, "note": "Reported when recording this store visit."}, now, "visit");
        }
        paid_items = [it for it in plan["items"] if it.get("actual_paid") is not None];
        plan["reported_paid_usd"] = round(sum([it["actual_paid"] for it in paid_items]), 2) if paid_items else None;
        plan["paid_items_count"] = len(paid_items);
        plan["status"] = "COMPLETED" if all([it["outcome"] != "PENDING" for it in plan["items"]]) else "IN_PROGRESS";
        # Purchased needs are removed by the usual feedback engine. Keep the remaining
        # checklist valid without treating a reported absence as global inventory data.
        plan["input_signature"] = signature(visit_context(p, now));
    } else { raise ValueError("Unsupported visit action."); }
    state.visit_plans = list(state.visit_plans);
    return "Store visit updated. Unpurchased needs remain on your list.";
}


def delivery_operation(p: UserProfile, action: str, data: dict, now: str) -> str {
    if (p.data_mode or get_settings()['data_mode']) != 'live' { raise ValueError('Choose Real stores first.'); }
    state = owned(p,ShoppingWorkspace); quotes = list(getattr(state,'delivery_quotes',[]));
    if action == 'save_delivery_quote' {
        quote = save_delivery_quote(data,visit_context(p,now),now);
        replace_id = data.get('replace_id');
        if replace_id and replace_id not in [q['id'] for q in quotes] { raise ValueError('The delivery quote to replace is no longer saved.'); }
        quotes = [q for q in quotes if q['id']!=replace_id];
        if len(quotes)>=3 { raise ValueError('Keep at most three delivery quotes; remove or replace one first.'); }
        quotes.append(quote);
    } elif action == 'remove_delivery_quote' { quotes = [q for q in quotes if q['id']!=data.get('id')]; }
    else { raise ValueError('Unknown delivery quote operation.'); }
    state.delivery_quotes = quotes;
    invalidate_visits(p,'A delivery checkout quote changed. Generate new comparisons.');
    return 'Delivery quote saved or removed. Compare plans again. This is user-entered checkout evidence, not an API quote or an order.';
}
