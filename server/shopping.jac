"""Structured operations for the shopping panel; no LLM/API key required."""

import math;
import json;
import from integrations.validation { need_spec }
import from models.events { ShoppingWorkspace }
import from models.graph { owned }
import from server.workflows { workflow, workspace_view, mode_of, save_need, invalidate_plans, refresh_live }
import from app_settings { get_settings, stamp, instant, quiet }
import from models.profile { UserProfile }
import from models.interest { InterestKind, InterestStatus }
import from models.catalog { Product, Offer }
import from models.graph { Has, profile_of, catalog_of, items_of, add_need, find_in }
import from providers.mock { load_mock, mock_updates }
import from interests.discovery { discover_products, discovery_action }
import from notify.reminders { inbox, reminder_action, suggestion_category }
import from interests.live { live_suggestions }
import from notify.background { set_background, background_view }
import from budget.ledger { add_expense, correct_expense, void_expense, budget_view, plan_budget_notes }
import from notify.delivery { set_delivery, test_delivery, delivery_view }
import from sync.engine { sync_events }

def shopping_operation(p: UserProfile, action: str, data: dict, now: str) -> dict {
    cfg = get_settings();
    cfg["data_mode"] = mode_of(p);
    now = stamp(now, cfg);
    cat = catalog_of(p);
    if cat.mode == "mock" and not [cat ->:Has:->][?:Product] { load_mock(cat, now=now); }
    # Upgrade persisted expired demo fixtures before comparing plans. Real quotes and
    # user observations are never rebased. Ordinary reads do not reset fresh data.
    if cat.mode == "mock" and action in ["view", "plan", "confirm_chat"] {
        renewals = [];
        for event in mock_updates(now=now) {
            o = find_in(cat, Offer, event["key"]);
            if o is not None and o.source == "mock" and not o.is_fresh(now) {
                renewals.append(event);
            }
        }
        if renewals { sync_events(p, renewals, now, cfg); }
    }
    refresh_requested = action == "refresh";
    message = "";
    if action == "save_interest" {
        category = data.get("category", "");
        if cfg["data_mode"] == "mock" and category not in [prod.category for prod in [cat ->:Has:->][?:Product]] {
            raise ValueError("Choose a category in the mock catalog");
        }
        kind = data.get("kind", "NEED");
        if kind not in ["NEED", "WATCH", "REPLENISH"] { raise ValueError("Unsupported interest type"); }
        price = float(data.get("target_price", 0));
        days = int(data.get("replenishment_days", 0));
        bought = data.get("last_purchased_at", "");
        if not math.isfinite(price) or price < 0 or days < 0 or days > 365 { raise ValueError("Invalid target price or replenishment interval"); }
        if kind == "WATCH" and price <= 0 { raise ValueError("Enter a positive target price"); }
        if kind == "REPLENISH" and (days < 1 or bought == "") { raise ValueError("Enter a purchase date and replenishment interval"); }
        if bought != "" and instant(bought) > instant(now) { raise ValueError("Purchase date cannot be in the future"); }
        item = save_need(p, data);
        invalidate_plans(p, "Shopping needs changed.");
        item.kind = InterestKind[kind];
        item.status = InterestStatus.ACTIVE;
        item.source = "USER";
        item.target_price = price;
        item.replenishment_days = days;
        item.last_purchased_at = stamp(bought, cfg) if bought != "" else "";
        message = "Interest saved.";
    } elif action == "discovery" {
        if not discovery_action(p, data.get("key", ""), data.get("action", "")) { raise ValueError("Recommendation is no longer active"); }
        message = "Recommendation updated.";
    } elif action == "reminder" and data.get("action") == "add" and suggestion_category(data.get("key", "")) != "" {
        key = data.get("key", "");
        if key not in [card["key"] for card in inbox(p, now, cfg)] { raise ValueError("This suggestion is no longer current."); }
        spec = {"category": suggestion_category(key), "qty": 1};
        # A sale is on one brand; keep it so the plan looks for the discounted product.
        if key.startswith("sale|") and key.split("|")[2].strip() != "" { spec["brand"] = key.split("|")[2].strip(); }
        item = save_need(p, spec);
        if item.kind == InterestKind.WATCH { item.kind = InterestKind.NEED; }
        invalidate_plans(p, "Shopping needs changed.");
        reminder_action(p, key, "dismiss", now, cfg);
        message = "Added " + spec["category"] + " to your list.";
    } elif action == "reminder" {
        if not reminder_action(p, data.get("key", ""), data.get("action", ""), now, cfg) { raise ValueError("Reminder is no longer actionable"); }
        message = "Reminder updated.";
    } elif action == "expense_add" {
        message = add_expense(p, data, now, "manual", cfg);
    } elif action == "expense_correct" {
        message = correct_expense(p, data, now, cfg);
    } elif action == "expense_void" {
        message = void_expense(p, data, now, cfg);
    } elif action == "notify_settings" {
        message = set_delivery(p, data);
    } elif action == "notify_test" {
        message = test_delivery(p);
    } elif action == "background" {
        message = set_background(p, data.get("enabled", False) == True);
    } elif action == "feedback" {
        sync_events(p, [data], now, cfg);
        message = "Feedback recorded.";
    } elif action == "sync" {
        if cfg["data_mode"] == "live" and any([e.get("type") == "offer" for e in data.get("events", [])]) { raise ValueError("Live offers can only be refreshed through the provider."); }
        result = sync_events(p, data.get("events", []), now, cfg);
        message = result["message"];
    } elif action == "interest_status" {
        invalidate_plans(p, "An interest was paused or archived.");
        status = data.get("status", "");
        if status not in ["ACTIVE", "PAUSED", "ARCHIVED"] { raise ValueError("Invalid interest status"); }
        for item in items_of(p) {
            if item.product_spec.get("type") == data.get("category") and item.kind != InterestKind.DISCOVER {
                item.status = InterestStatus[status];
                if status == "ACTIVE" { item.in_current_list = True; }
            }
        }
    } elif action == "confirm_chat" {
        state = owned(p, ShoppingWorkspace);
        if data.get("id") != state.pending_id or not state.pending_intent { raise ValueError("This chat proposal is no longer pending."); }
        proposal = state.pending_intent;
        if proposal.get("feedback") {
            if proposal["profile"] or proposal["needs"] or proposal["address"] { raise ValueError("Confirm feedback separately from profile or need changes."); }
            event = dict(proposal["feedback"]);
            event["id"] = state.pending_id;
            event["type"] = "feedback";
            sync_events(p, [event], now, cfg);
        } else {
            # Run address lookup first so missing credentials do not partially apply a request.
            if proposal["address"] { workflow(p, "geocode", {"address": proposal["address"]}, now); }
            current = [n.product_spec["type"] for n in items_of(p) if n.plannable()];
            if len(set(current + [n["type"] for n in proposal["needs"]])) > 6 { raise ValueError("Use at most six active needs."); }
            if proposal["profile"] { workflow(p, "update_profile", proposal["profile"], now); }
            for spec in proposal["needs"] { save_need(p, spec); }
            if proposal["needs"] { invalidate_plans(p, "Shopping request changed."); }
        }
        # Consume the proposal before optional subsequent queries; retry never reapplies feedback.
        state.pending_intent = {};
        state.pending_id = "";
        message = "Changes saved.";
        if proposal["address"] { message += " Confirm an address result, then find nearby stores."; }
        elif proposal["intent"] == "plan" { message = workflow(p, "plan", {}, now); }
        elif proposal["intent"] == "search" and cfg["data_mode"] == "live" { message = workflow(p, "nearby", {}, now); }
        elif proposal["intent"] == "products" { message = workflow(p, "historical_prices", {"store": proposal.get("store_id", "")}, now); }
        elif proposal["intent"] == "refresh" { refresh_requested = True; }
    } elif action == "discard_chat" {
        state = owned(p, ShoppingWorkspace);
        state.pending_intent = {}; state.pending_id = "";
        message = "Chat proposal discarded.";
    } elif action not in ["refresh", "view", "discover", "background", "expense_add", "expense_correct", "expense_void", "notify_settings", "notify_test"] {
        message = workflow(p, action, data, now);
        cfg["data_mode"] = mode_of(p);
        cat = catalog_of(p);
        if cat.mode == "mock" and not [cat ->:Has:->][?:Product] { load_mock(cat, now=now); }
    }
    if action not in ["view", "background", "expense_add", "expense_correct", "expense_void", "notify_settings", "notify_test"] {
        if refresh_requested and cfg["data_mode"] == "live" { refresh_live(p); }
        updates = [];
        if refresh_requested and cfg["data_mode"] == "mock" {
            for event in mock_updates(now=now) {
                o = find_in(cat, Offer, event["key"]);
                if o is not None and o.source != "user" { updates.append(event); }
            }
        }
        sync_events(p, updates, now, cfg);
        discover_products(p, now, cfg);
    }
    if cfg["data_mode"] == "live" and action in ["view", "refresh"] { live_suggestions(p, now, refresh_requested); }
    discoveries = [];
    for item in items_of(p) {
        if item.kind == InterestKind.DISCOVER and item.status == InterestStatus.ACTIVE {
            prod = find_in(cat, Product, item.product_spec["product_key"]);
            if prod is None { continue; }
            discoveries.append({"key": prod.key, "name": prod.name, "reason": item.discovery_reason});
        }
    }
    needs = [{"category": n.product_spec.get("type", ""), "kind": n.kind.name, "status": n.status.name,
              "qty": n.product_spec.get("qty", 1), "brand": n.product_spec.get("brand", ""), "variant": n.product_spec.get("variant", ""), "size": n.product_spec.get("size", ""),
              "in_current_list": getattr(n, "in_current_list", True)}
             for n in items_of(p) if n.kind != InterestKind.DISCOVER and n.status != InterestStatus.ARCHIVED];
    workspace = workspace_view(p, now);
    workspace["budget_notes"] = plan_budget_notes(p, workspace["plans"] + workspace["visit_plans"], now, cfg);
    return {"message": message, "discoveries": discoveries, "reminders": inbox(p, now, cfg),
            "interests": needs, "categories": sorted(set([prod.category for prod in [cat ->:Has:->][?:Product]])),
            "quiet": quiet(now, cfg), "background": background_view(p, now, cfg), "budget": budget_view(p, now, cfg), "delivery": delivery_view(p), "data_mode": cfg["data_mode"], "checked_at": now, "workspace": workspace};
}

walker:pub ShoppingAction {
    has action: str = "view", data: dict = {};
    can run with Root entry {
        try {
            report shopping_operation(profile_of(here), self.action, self.data, stamp());
        } except ValueError as err {
            report {"error": str(err)};
        }
    }
}
