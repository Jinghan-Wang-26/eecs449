import from app_settings { get_settings, due, stamp }
import from models.profile { UserProfile }
import from models.interest { InterestPool, InterestKind, InterestStatus }
import from models.catalog { Product, Offer, Availability }
import from models.events { SyncState, ReminderStatus }
import from models.plan { PlanStatus }
import from models.graph { Owns, owned, catalog_of, add_need, items_of, find_in, want, mark_disliked, reminders_of, plans_of, plan_items_of, offer_of, legs_of }
import from providers.mock { load_mock }
import from interests.discovery { discover_products, discovery_action }
import from notify.reminders { check_reminders, inbox, reminder_action }
import from sync.engine { sync_events }
import from planning.lifecycle { plan_shopping, accept }
import from server.shopping { shopping_operation, ShoppingAction }

glob NOW: str = "2026-10-12T10:00:00-04:00";

def user() -> UserProfile {
    p = UserProfile(transport=["WALK", "BUS"], free_windows=["SAT 14:00-17:00"], weekly_budget=100);
    p +>:Owns:+> InterestPool();
    load_mock(catalog_of(p));
    return p;
}

def update(key: str, id: str, price: float) -> dict {
    return {"id": id, "type": "offer", "key": key, "fields": {
        "price": price, "observed_at": NOW, "valid_until": "2026-10-17T10:00:00-04:00"
    }};
}

test "application limits change actual plan generation" {
    p = user();
    add_need(p, {"type": "milk"});
    assert len(plan_shopping(p, NOW, {"max_plan_options": 1})["plans"]) == 1;
    failed = False;
    try { get_settings({"max_plan_options": 0}); } except ValueError { failed = True; }
    assert failed;
    failed = False;
    try { get_settings({"data_mode": "invalid"}); } except ValueError { failed = True; }
    assert failed;
    assert due("2026-10-12T14:00:00+00:00", NOW);
}

test "discovery is limited per week and needs confirmation" {
    p = user();
    add_need(p, {"type": "yogurt"});
    added = discover_products(p, NOW, {"max_discovery_items_per_week": 1});
    assert len(added) == 1 and not added[0].plannable();
    assert discover_products(p, NOW, {"max_discovery_items_per_week": 1}) == [];
    assert added[0].discovery_reason != "";
    assert discovery_action(p, added[0].product_spec["product_key"], "accept");
    assert len([i for i in items_of(p) if i.plannable()]) == 1;
}

test "disliked products and unverified dietary matches are excluded" {
    p = user();
    n = add_need(p, {"type": "yogurt"});
    prod = find_in(catalog_of(p), Product, "yogurt-honey-32oz");
    want(n, prod);
    mark_disliked(n, prod);
    added = discover_products(p, NOW);
    assert len(added) == 1 and added[0].product_spec["product_key"] == "yogurt-plain-32oz";
    assert discovery_action(p, "yogurt-plain-32oz", "dismiss");
    assert discover_products(p, "2026-10-19T10:00") == [];
    p2 = user();
    p2.dietary = ["vegan"];
    add_need(p2, {"type": "yogurt"});
    assert discover_products(p2, NOW) == [];
}

test "replenishment respects purchases pause snooze and deduplication" {
    p = user();
    n = add_need(p, {"type": "milk"});
    n.kind = InterestKind.REPLENISH;
    n.replenishment_days = 7;
    n.last_purchased_at = "2026-10-01T10:00";
    assert len(check_reminders(p, NOW)) == 1;
    assert check_reminders(p, NOW) == [];
    assert len(inbox(p, NOW)) == 1;
    n.status = InterestStatus.PAUSED;
    assert inbox(p, NOW) == [];
    n.status = InterestStatus.ACTIVE;
    n.snoozed_until = "2026-10-14T10:00";
    assert inbox(p, NOW) == [];
    n.snoozed_until = "";
    n.last_purchased_at = NOW;
    assert inbox(p, NOW) == [];
}

test "price and restock reminders need fresh evidence" {
    p = user();
    n = add_need(p, {"type": "laundry detergent"});
    n.kind = InterestKind.WATCH;
    n.target_price = 10;
    # The member-only 9.49 offer must not notify a non-member.
    assert check_reminders(p, NOW) == [];
    ev = update("corner:detergent-92oz:IN_STORE", "restock-1", 8.0);
    ev["fields"]["availability"] = "IN_STOCK";
    result = sync_events(p, [ev], NOW);
    assert result["new_reminders"] == 2;
    assert len(inbox(p, NOW)) == 2;
    assert sync_events(p, [ev], NOW)["applied"] == 0;
    assert check_reminders(p, NOW) == [];
    assert inbox(p, "2026-10-20T10:00") == [];
}

test "quiet hours and explicit reminder actions affect delivery" {
    p = user();
    n = add_need(p, {"type": "milk"});
    n.kind = InterestKind.WATCH;
    n.target_price = 4.3;
    check_reminders(p, NOW);
    assert inbox(p, "2026-10-12T23:00") == [];
    cards = inbox(p, NOW);
    key = cards[0]["key"];
    assert reminder_action(p, key, "ignore", NOW, {"reminder_cooldown_hours": 1});
    assert key not in [c["key"] for c in inbox(p, "2026-10-12T11:00")];
    assert key in [c["key"] for c in inbox(p, "2026-10-12T12:00")];
    assert reminder_action(p, key, "dismiss", "2026-10-12T12:00");
    assert key not in [c["key"] for c in inbox(p, "2026-10-12T13:00")];
}

test "a batch replans once and replays without changes" {
    p = user();
    add_need(p, {"type": "milk"});
    old = plan_shopping(p, NOW)["plans"];
    evs = [update("huron:milk-whole-1gal:IN_STORE", "p1", 9.0), update("huron:milk-whole-1gal:PICKUP", "p2", 9.0), update("corner:milk-whole-1gal:IN_STORE", "p3", 9.0)];
    result = sync_events(p, evs, NOW);
    assert result["replanned"] and owned(p, SyncState).replan_count == 1;
    assert all([x.status == PlanStatus.CANCELLED for x in old]);
    assert not sync_events(p, evs, NOW)["replanned"];
    assert owned(p, SyncState).replan_count == 1;
}

test "accepted plans require review and price noise does not replan" {
    p = user();
    add_need(p, {"type": "milk"});
    plan = plan_shopping(p, NOW)["plans"][0];
    accept(p, plan);
    o = offer_of(plan_items_of(plan)[0]);
    assert not sync_events(p, [update(o.key, "tiny", o.price + 0.01)], NOW)["replanned"];
    assert plan.status == PlanStatus.ACCEPTED;
    result = sync_events(p, [update(o.key, "large", o.price + 3.0)], NOW);
    assert result["reviewed"] == 1 and not result["replanned"];
    assert plan.status == PlanStatus.NEEDS_REVIEW;
    assert len([r for r in reminders_of(p) if r.kind == "PLAN_CHANGE"]) == 1;
    assert sync_events(p, [], NOW)["reviewed"] == 0;
}

test "invalid batches and conflicting event ids cannot partly mutate offers" {
    p = user();
    key = "huron:milk-whole-1gal:IN_STORE";
    o = find_in(catalog_of(p), Offer, key);
    before = o.price;
    failed = False;
    try { sync_events(p, [update(key, "ok", 1.0), update("missing", "bad", 1.0)], NOW); } except ValueError { failed = True; }
    assert failed and o.price == before;
    ev = update(key, "ok", 1.0);
    sync_events(p, [ev], NOW);
    failed = False;
    try { sync_events(p, [update(key, "ok", 2.0)], NOW); } except ValueError { failed = True; }
    assert failed and o.price == 1.0;
}

test "purchase feedback replays once and never learns lasting preferences" {
    p = user();
    n = add_need(p, {"type": "milk"});
    plan = plan_shopping(p, NOW)["plans"][0];
    accept(p, plan);
    ev = {"id": "purchase", "type": "feedback", "target": "milk", "reason": "PURCHASED"};
    assert sync_events(p, [ev], NOW)["applied"] == 1;
    assert plan.status == PlanStatus.COMPLETED and n.status == InterestStatus.ARCHIVED;
    assert sync_events(p, [ev], NOW)["applied"] == 0;
    assert p.brand_prefs == {};
}

test "busy feedback preserves interest and explicit trip changes preserve profile" {
    p = user();
    n = add_need(p, {"type": "milk"});
    sync_events(p, [{"id": "busy", "type": "feedback", "target": "milk", "reason": "BUSY", "until": "2026-10-14T10:00"}], NOW);
    assert n.status == InterestStatus.ACTIVE and n.priority == 2;
    assert plan_shopping(p, NOW)["plans"] == [];
    sync_events(p, [{"id": "budget", "type": "feedback", "target": "milk", "reason": "TOO_EXPENSIVE", "trip": {"budget": 20}}], NOW);
    assert p.weekly_budget == 100;
}

test "the structured panel saves interests and returns recommendations and reminders" {
    p = user();
    result = shopping_operation(p, "save_interest", {"category": "milk", "kind": "WATCH", "target_price": "4.30"}, NOW);
    assert len(result["interests"]) == 1 and result["discoveries"] and result["reminders"];
    key = result["discoveries"][0]["key"];
    result = shopping_operation(p, "discovery", {"key": key, "action": "accept"}, NOW);
    assert len([n for n in items_of(p) if n.plannable()]) == 1;
    assert len([n for n in items_of(p) if n.kind != InterestKind.DISCOVER]) == 1;
    shopping_operation(p, "interest_status", {"category": "milk", "status": "PAUSED"}, NOW);
    assert shopping_operation(p, "refresh", {}, NOW)["reminders"] == [];
}

test "purchased replenishment stays out of plans until the next cycle" {
    p = user();
    n = add_need(p, {"type": "milk"});
    n.kind = InterestKind.REPLENISH;
    n.replenishment_days = 7;
    sync_events(p, [{"id": "replenish-buy", "type": "feedback", "target": "milk", "reason": "PURCHASED"}], NOW);
    assert n.status == InterestStatus.ACTIVE and n.snoozed_until != "";
    assert plan_shopping(p, NOW)["plans"] == [];
    assert check_reminders(p, NOW) == [];
    assert len(check_reminders(p, "2026-10-19T10:01")) == 1;
}

test "new cheaper alternatives trigger one proposal refresh" {
    p = user();
    add_need(p, {"type": "milk"});
    plan_shopping(p, NOW);
    result = sync_events(p, [update("corner:milk-whole-1gal:IN_STORE", "cheaper", 0.5)], NOW);
    assert result["replanned"] and owned(p, SyncState).replan_count == 1;
}

test "old provider responses do not overwrite newer observations" {
    p = user();
    key = "huron:milk-whole-1gal:IN_STORE";
    sync_events(p, [update(key, "newer", 5.0)], NOW);
    ev = update(key, "older", 1.0);
    ev["fields"]["observed_at"] = "2026-10-11T10:00";
    sync_events(p, [ev], NOW);
    assert find_in(catalog_of(p), Offer, key).price == 5.0;
}

test "sent reminders do not repeat unchanged after cooldown" {
    p = user();
    n = add_need(p, {"type": "milk"});
    n.kind = InterestKind.WATCH;
    n.target_price = 4.3;
    check_reminders(p, NOW);
    inbox(p, NOW);
    count = len(reminders_of(p));
    assert check_reminders(p, "2026-10-14T10:00") == [];
    assert len(reminders_of(p)) == count;
}

test "explicit trip feedback sends an accepted plan to review" {
    p = user();
    add_need(p, {"type": "milk"});
    plan = plan_shopping(p, NOW)["plans"][0];
    accept(p, plan);
    result = sync_events(p, [{"id": "lower-budget", "type": "feedback", "target": "milk", "reason": "TOO_EXPENSIVE", "trip": {"budget": 5}}], NOW);
    assert result["reviewed"] == 1 and plan.status == PlanStatus.NEEDS_REVIEW;
    assert p.weekly_budget == 100;
}

test "channel settings constrain actual saved plans" {
    p = user();
    add_need(p, {"type": "milk"});
    options = plan_shopping(p, NOW, {"max_fulfillment_channels": 1})["plans"];
    assert options and all([len(legs_of(plan)) == 1 for plan in options]);
}

test "expired offers never create new price or restock notifications" {
    p = user();
    n = add_need(p, {"type": "milk"});
    n.kind = InterestKind.WATCH;
    n.target_price = 100;
    assert check_reminders(p, "2026-10-20T10:00") == [];
    assert reminders_of(p) == [];
}

test "multiple feedback events in one batch preserve purchase idempotency" {
    p = user();
    n = add_need(p, {"type": "milk"});
    event = {"id": "batch-purchase", "type": "feedback", "target": "milk", "reason": "PURCHASED"};
    assert sync_events(p, [event, event], NOW)["applied"] == 1;
    assert n.last_purchased_at == stamp(NOW);
    assert not owned(p, SyncState).syncing;
}

test "mock refresh preserves more recent user feedback and price changes" {
    p = user();
    key = "huron:milk-whole-1gal:IN_STORE";
    sync_events(p, [update(key, "new-price", 2.0)], NOW);
    shopping_operation(p, "refresh", {}, NOW);
    assert find_in(catalog_of(p), Offer, key).price == 2.0;
}
