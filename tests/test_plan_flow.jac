"""Planning against the mock catalog: inputs, saved plans, and the plan lifecycle."""

import from models.profile { UserProfile }
import from models.interest { InterestPool, InterestStatus }
import from models.plan { PlanStatus, ItemOutcome }
import from models.catalog { Catalog, Store, Offer, Availability }
import from models.events { FeedbackReason }
import from models.graph {
    Owns, add_need, catalog_of, find_in, items_of, legs_of, plan_items_of, offer_of, store_of, merchandise
}
import from providers.mock { load_mock }
import from planning.inputs { expand_days, hours_windows, pick_route, channels_for, quotes_for }
import from planning.lifecycle { plan_shopping, accept, record_outcome, review_changes }

glob NOW: str = "2026-10-10T09:00";

"""The README errand: no car, 6 kg, $60, free Saturday afternoon. Off root, so tests do not share state."""
def errand(keys: list = ["milk", "eggs", "rice", "laundry detergent"]) -> UserProfile {
    p = UserProfile(transport=["WALK", "BUS"], carry_limit_kg=6.0, weekly_budget=60.0,
                    free_windows=["SAT 14:00-17:00"]);
    p +>:Owns:+> InterestPool();
    load_mock(catalog_of(p));
    for key in keys {
        add_need(p, {"type": key, "qty": 1});
    }
    return p;
}

def ctx_for(p: UserProfile) -> dict {
    return {"transport": p.transport};
}

def need(p: UserProfile, key: str) -> any {
    return [i for i in items_of(p) if i.product_spec["type"] == key][0];
}

test "store hours expand into daily windows" {
    assert expand_days("MON-FRI") == ["MON", "TUE", "WED", "THU", "FRI"];
    assert expand_days("SAT") == ["SAT"];
    assert "SUN 09:00-20:00" in hours_windows({"MON-FRI": "07:00-22:00", "SUN": "09:00-20:00"});
}

test "a trip uses the fastest route the user can take" {
    p = errand([]);
    cat = catalog_of(p);
    huron = find_in(cat, Store, "huron");
    assert pick_route(huron, ["WALK", "BUS"])[0] == "BUS";
    assert pick_route(huron, ["WALK"])[0] == "WALK";
    # no allowed route: keep the fastest so the constraint check can name the mode
    assert pick_route(find_in(cat, Store, "bulk"), ["WALK"])[0] == "CAR";
}

test "catalog channels cover in-store, pickup, and delivery" {
    p = errand([]);
    ids = sorted([c.id for c in channels_for(catalog_of(p), ctx_for(p))]);
    assert ids == ["bulk:DELIVERY", "bulk:IN_STORE", "corner:IN_STORE", "huron:IN_STORE", "huron:PICKUP", "quick:DELIVERY"];
}

test "quotes carry member prices, stock, and skip unknown prices" {
    p = errand(["rice"]);
    found = quotes_for(p, catalog_of(p), NOW);
    bulk = [q for q in found["quotes"] if q.channel == "bulk:IN_STORE"][0];
    assert bulk.discount == 3.0 and bulk.member_only == "ARBOR_CLUB" and bulk.weight_kg == 9.1;
    assert not [q for q in found["quotes"] if q.channel == "quick:DELIVERY"];
    assert any(["no price yet at" in n for n in found["notes"]]);
}

test "an out-of-stock offer is never planned" {
    p = errand(["laundry detergent"]);
    found = quotes_for(p, catalog_of(p), NOW);
    corner = [q for q in found["quotes"] if q.channel == "corner:IN_STORE"][0];
    assert corner.stock == "NO";
    for plan in plan_shopping(p, NOW)["plans"] {
        assert "corner:detergent-92oz:IN_STORE" not in [offer_of(pi).key for pi in plan_items_of(plan)];
    }
}

test "expired offers are not used" {
    p = errand(["milk"]);
    assert quotes_for(p, catalog_of(p), "2026-10-20T00:00")["quotes"] == [];
}

test "saved plans meet the limits and snapshot their prices" {
    p = errand();
    result = plan_shopping(p, NOW);
    assert result["plans"];
    for plan in result["plans"] {
        assert plan.status == PlanStatus.PROPOSED;
        assert plan.carried_kg <= 6.0 and plan.total <= 60.0;
        assert len(plan_items_of(plan)) == 4;
        for leg in legs_of(plan) {
            assert store_of(leg) is not None;
        }
        m = merchandise(plan);
        assert m["unknown"] == [];
        assert abs(m["subtotal"] - (plan.cost["merchandise"] - plan.cost["discounts"])) < 0.01;
    }
}

test "no feasible plan explains why" {
    p = errand();
    p.carry_limit_kg = 1.0;
    p.free_windows = ["SAT 14:00-15:00"];              # misses every delivery window
    result = plan_shopping(p, NOW);
    assert result["plans"] == [];
    assert "No plan meets" in result["message"] and "kg" in result["message"];
}

test "lifecycle: accept, partial outcomes, completion" {
    p = errand();
    plans = plan_shopping(p, NOW)["plans"];
    chosen = plans[0];
    assert accept(p, chosen);
    assert all([x.status == PlanStatus.CANCELLED for x in plans if x != chosen]);
    det = [pi for pi in plan_items_of(chosen) if pi.name == "laundry detergent"][0];
    for pi in plan_items_of(chosen) {
        reason = FeedbackReason.OUT_OF_STOCK if pi.name == "laundry detergent" else FeedbackReason.PURCHASED;
        assert record_outcome(p, chosen, pi.name, reason, "ev-" + pi.name, "2026-10-11T15:00");
    }
    assert chosen.status == PlanStatus.COMPLETED;
    assert need(p, "milk").status == InterestStatus.ARCHIVED;
    assert need(p, "laundry detergent").status == InterestStatus.ACTIVE;
    assert det.outcome == ItemOutcome.UNAVAILABLE and offer_of(det).availability == Availability.OUT;
}

test "the same event is not applied twice" {
    p = errand();
    plan = plan_shopping(p, NOW)["plans"][0];
    accept(p, plan);
    assert record_outcome(p, plan, "milk", FeedbackReason.PURCHASED, "ev-1");
    assert not record_outcome(p, plan, "milk", FeedbackReason.PURCHASED, "ev-1");
}

test "a price change sends an accepted plan to review, but only replans a proposal" {
    p = errand();
    plan = plan_shopping(p, NOW)["plans"][0];
    o = offer_of(plan_items_of(plan)[0]);
    o.price = o.price + 2.0;
    o.member_price = None;
    assert review_changes(p, plan, NOW)["action"] == "replan";
    accept(p, plan);
    result = review_changes(p, plan, NOW);
    assert result["action"] == "review" and result["changes"][0]["field"] == "price";
    assert plan.status == PlanStatus.NEEDS_REVIEW and "Needs review" in plan.explanation;
}

test "replanning cancels old proposals" {
    p = errand();
    first = plan_shopping(p, NOW)["plans"];
    plan_shopping(p, NOW);
    assert all([x.status == PlanStatus.CANCELLED for x in first]);
}
