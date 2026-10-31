"""Persistent historical store visits, separate from current-price ShoppingPlan/Offer."""
import from app_settings { due, instant, get_settings }
import from planning.visits { recommend, signature }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from models.graph { owned, items_of }
import from sync.engine { sync_events }
import from integrations.validation { purchase_result }


def visit_context(p: UserProfile, now: str) -> dict {
    state = owned(p, ShoppingWorkspace);
    return {"origin": p.location, "radius_m": state.search_radius_m,
        "needs": [dict(n.product_spec) for n in items_of(p) if n.plannable() and (n.snoozed_until == "" or due(n.snoozed_until, now))],
        "profile": {"transport": p.transport, "max_walk_min": p.max_walk_min,
            "free_windows": p.free_windows, "weekly_budget": p.weekly_budget,
            "carry_limit_kg": p.carry_limit_kg, "dietary": p.dietary,
            "transport_cost": p.transport_cost, "memberships": p.memberships}};
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
        expired = plan["route"] is not None and not due(now, plan["route"]["valid_until"]);
        departed = plan["route"] is not None and bool(plan["route"].get("departure_at")) and due(plan["route"]["departure_at"], now);
        if changed or expired or (departed and plan["status"] == "PROPOSED") {
            plan["status"] = "NEEDS_REVIEW";
            plan["accept_allowed"] = False;
            plan["review_reason"] = "Inputs changed, the route estimate expired, or the proposed departure passed. Generate and review a new visit plan.";
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
    return f"Generated {len(proposals)} historical store-visit options. Review coverage, route limits and unknown current prices before accepting.";
}

def visit_action(p: UserProfile, data: dict, now: str) -> str {
    if (p.data_mode or get_settings()["data_mode"]) != "live" { raise ValueError("Choose Real stores first."); }
    state = owned(p, ShoppingWorkspace);
    plans = visit_view(p, now);
    found = [plan for plan in plans if plan["key"] == data.get("key")];
    if len(found) != 1 { raise ValueError("Visit plan not found. Generate new recommendations."); }
    plan = found[0]; action = data.get("action");
    if action == "accept" {
        if plan["status"] != "PROPOSED" or not plan["accept_allowed"] { raise ValueError("This visit needs new recommendations or corrected travel constraints."); }
        if data.get("acknowledge_unknowns") is not True { raise ValueError("Acknowledge that current prices, stock and opening hours need checking."); }
        if any([other["status"] in ["ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"] for other in plans if other["key"] != plan["key"] and other.get("accepted_at")]) {
            raise ValueError("Complete or cancel your existing visit before accepting another.");
        }
        plan["status"] = "ACCEPTED";
        plan["accepted_at"] = now;
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
