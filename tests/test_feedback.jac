import from models.profile { UserProfile }
import from models.interest { InterestPool, InterestKind, InterestStatus }
import from models.plan { ShoppingPlan, ItemOutcome }
import from models.catalog { Catalog, Offer, Product, Store, Availability }
import from models.events { FeedbackReason, ReminderStatus }
import from models.graph {
    Owns, add_need, catalog_of, find_in, want, usable_products, add_leg, add_plan_item,
    feedback_of, about_of, add_reminder, due_reminders, reminders_of
}
import from providers.mock { load_mock }
import from feedback.apply { record_feedback }

def loaded() -> tuple {
    p = UserProfile();
    p +>:Owns:+> InterestPool();
    cat = catalog_of(p);
    load_mock(cat);
    return (p, cat);
}

"""A one-item plan at the offer's store. Returns (need, plan item, offer)."""
def planned(p: UserProfile, cat: Catalog, spec: dict, offer_key: str, kind: InterestKind = InterestKind.NEED) -> tuple {
    o = find_in(cat, Offer, offer_key);
    parts = offer_key.split(":");
    need = add_need(p, spec);
    need.kind = kind;
    want(need, find_in(cat, Product, parts[1]));
    plan = ShoppingPlan();
    p +>:Owns:+> plan;
    leg = add_leg(plan, find_in(cat, Store, parts[0]), parts[2]);
    return (need, add_plan_item(leg, need, o), o);
}

test "a duplicate purchase event is applied once" {
    (p, cat) = loaded();
    (milk, pi, o) = planned(p, cat, {"type": "milk", "qty": 1}, "huron:milk-whole-1gal:IN_STORE");
    assert record_feedback(p, "evt-1", FeedbackReason.PURCHASED, [pi], at="2026-10-11T15:00");
    milk.last_purchased_at = "";
    assert not record_feedback(p, "evt-1", FeedbackReason.PURCHASED, [pi], at="2026-10-11T15:00");
    assert milk.last_purchased_at == "";
    assert pi.outcome == ItemOutcome.PURCHASED and milk.status == InterestStatus.ARCHIVED;
    assert len(feedback_of(pi)) == 1 and about_of(feedback_of(pi)[0]) == [pi];
}

test "a replenish purchase keeps the item active" {
    (p, cat) = loaded();
    (milk, pi, o) = planned(p, cat, {"type": "milk", "qty": 1}, "huron:milk-whole-1gal:IN_STORE", InterestKind.REPLENISH);
    record_feedback(p, "evt-2", FeedbackReason.PURCHASED, [pi], at="2026-10-11T15:00");
    assert milk.status == InterestStatus.ACTIVE and milk.last_purchased_at == "2026-10-11T15:00";
}

test "a stockout marks the offer and keeps the need" {
    (p, cat) = loaded();
    (soap, pi, o) = planned(p, cat, {"type": "laundry detergent", "qty": 1}, "huron:detergent-92oz:IN_STORE");
    soap.priority = 1;
    record_feedback(p, "evt-3", FeedbackReason.OUT_OF_STOCK, [pi], at="2026-10-11T15:00");
    assert pi.outcome == ItemOutcome.UNAVAILABLE;
    assert o.availability == Availability.OUT and o.source == "user" and o.observed_at == "2026-10-11T15:00";
    assert soap.status == InterestStatus.ACTIVE and soap.priority == 1;
}

test "a dislike removes one product, not the need" {
    (p, cat) = loaded();
    (yogurt, pi, o) = planned(p, cat, {"type": "yogurt", "qty": 1}, "corner:yogurt-honey-32oz:IN_STORE");
    plain = find_in(cat, Product, "yogurt-plain-32oz");
    want(yogurt, plain);
    record_feedback(p, "evt-4", FeedbackReason.DISLIKED, [pi], text="too sweet");
    assert usable_products(yogurt) == [plain] and yogurt.status == InterestStatus.ACTIVE;
}

test "feedback can target a need directly" {
    (p, cat) = loaded();
    eggs = add_need(p, {"type": "eggs", "qty": 1});
    eggs.kind = InterestKind.REPLENISH;
    record_feedback(p, "evt-5", FeedbackReason.HAVE_AT_HOME, [eggs], until="2026-10-18T00:00");
    assert eggs.snoozed_until == "2026-10-18T00:00" and len(feedback_of(eggs)) == 1;
}

test "reminders dedupe by key and respect the cooldown" {
    (p, cat) = loaded();
    milk = add_need(p, {"type": "milk", "qty": 1});
    key = "replenish:milk:2026-10-12";
    r = add_reminder(p, key, "REPLENISH", "Running low on milk?", "2026-10-12T09:00", [milk], now="2026-10-11T09:00");
    assert r is not None and about_of(r) == [milk];
    assert add_reminder(p, key, "REPLENISH", "again", "2026-10-12T09:00", [milk], now="2026-10-11T10:00") is None;
    assert due_reminders(p, "2026-10-12T08:00") == [] and due_reminders(p, "2026-10-12T09:00") == [r];
    r.status = ReminderStatus.SENT;
    assert add_reminder(p, key, "REPLENISH", "again", "2026-10-12T09:00", [milk], now="2026-10-11T20:00") is None;
    assert add_reminder(p, key, "REPLENISH", "again", "2026-10-13T09:00", [milk], now="2026-10-12T10:00") is not None;
    r.status = ReminderStatus.DISMISSED;
    assert add_reminder(p, "price:x", "PRICE_DROP", "", "", [], now="2026-10-12T10:00") is not None;
    assert len(reminders_of(p)) == 3;
}
