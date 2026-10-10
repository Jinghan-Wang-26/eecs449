"""Planning core on hand-built channels and quotes. README example 2: milk, eggs, rice, detergent
by Saturday; no car, 6 kg limit, $60 budget."""

import from models.profile { UserProfile, TripConstraints, effective_constraints }
import from models.interest { InterestPool }
import from models.graph { Owns, add_need }
import from planning.types { Need, Channel, Quote, Candidate, first_fit }
import from planning.cost { basket_cost }
import from planning.candidates { build_candidates, evaluate, select_options, worth_the_time }

def demo_channels() -> list {
    return [
        Channel(id="kroger-store", store="Kroger", kind="IN_STORE", mode="BUS",
                travel_min=50, shop_min=20, walk_min=10, transfers=1, transport_cost=3.0,
                windows=["SAT 07:00-23:00", "SUN 07:00-23:00"]),
        Channel(id="kroger-delivery", store="Kroger", kind="DELIVERY",
                delivery_fee=7.99, service_fee_pct=0.05, tip=5.0, min_order=10.0,
                windows=["FRI 16:00-20:00", "SAT 14:00-17:00"], ready_day="FRI"),
        Channel(id="corner-store", store="Corner Market", kind="IN_STORE", mode="WALK",
                travel_min=15, shop_min=10, walk_min=8,
                windows=["SAT 08:00-22:00"])
    ];
}

def demo_quotes() -> list {
    return [
        Quote(need="milk", channel="kroger-store", price=3.49, weight_kg=2.0),
        Quote(need="eggs", channel="kroger-store", price=3.99, weight_kg=0.7),
        Quote(need="rice", channel="kroger-store", price=7.99, weight_kg=4.5),
        Quote(need="detergent", channel="kroger-store", price=11.99, weight_kg=2.5),
        Quote(need="milk", channel="kroger-delivery", price=4.29, weight_kg=2.0),
        Quote(need="eggs", channel="kroger-delivery", price=4.79, weight_kg=0.7),
        Quote(need="rice", channel="kroger-delivery", price=8.99, weight_kg=4.5),
        Quote(need="detergent", channel="kroger-delivery", price=12.99, weight_kg=2.5),
        Quote(need="milk", channel="corner-store", price=4.49, weight_kg=2.0),
        Quote(need="eggs", channel="corner-store", price=4.99, weight_kg=0.7, stock="UNKNOWN")
    ];
}

def demo_profile() -> UserProfile {
    p = UserProfile(transport=["WALK", "BUS"], carry_limit_kg=6.0, weekly_budget=60.0,
                    free_windows=["SAT 14:00-17:00"]);
    p +>:Owns:+> InterestPool();
    for key in ["milk", "eggs", "rice", "detergent"] {
        add_need(p, {"type": key, "qty": 1});
    }
    return p;
}

def demo_needs() -> list {
    return [Need(key="milk"), Need(key="eggs"), Need(key="rice"), Need(key="detergent")];
}

def by_id(items: list) -> dict {
    out = {};
    for x in items {
        out[x.id] = x;
    }
    return out;
}

def by_key(items: list) -> dict {
    out = {};
    for x in items {
        out[x.key] = x;
    }
    return out;
}

def evaluated(p: UserProfile) -> list {
    chans = by_id(demo_channels());
    needs = demo_needs();
    ctx = effective_constraints(p, None);
    ctx["deadline"] = "SAT";
    cands = build_candidates(needs, chans, demo_quotes());
    for c in cands {
        evaluate(c, by_key(needs), chans, ctx, p.memberships);
    }
    return cands;
}

test "in-store cost adds tax and bus fare" {
    chans = by_id(demo_channels());
    qs = demo_quotes();
    cb = basket_cost({"milk": qs[0], "eggs": qs[1]}, by_key(demo_needs()), chans, []);
    assert cb.total() == 10.93;       # 7.48 + 6% tax + $3 fare
}

test "delivery adds fee, service fee, and tip; free threshold removes the fee" {
    chans = by_id(demo_channels());
    qs = demo_quotes();
    cb = basket_cost({"rice": qs[6], "detergent": qs[7]}, by_key(demo_needs()), chans, []);
    assert cb.delivery_fees == 7.99 and cb.tips == 5.0;
    chans["kroger-delivery"].free_over = 20.0;
    assert basket_cost({"rice": qs[6], "detergent": qs[7]}, by_key(demo_needs()), chans, []).delivery_fees == 0.0;
}

test "member price applies only with the membership" {
    chans = by_id(demo_channels());
    q = Quote(need="milk", channel="kroger-store", price=3.49, discount=0.5, member_only="Kroger Plus");
    needs = by_key(demo_needs());
    assert basket_cost({"milk": q}, needs, chans, []).discounts == 0.0;
    assert basket_cost({"milk": q}, needs, chans, ["Kroger Plus"]).discounts == 0.5;
}

test "store and delivery windows must meet the user's free time" {
    assert first_fit(["SAT 14:00-17:00"], ["SAT 07:00-23:00"], 70) == "SAT";
    assert first_fit(["SAT 14:00-15:00"], ["SAT 07:00-23:00"], 70) == "";
    assert first_fit(["SAT 14:00-17:00"], ["FRI 16:00-20:00", "SAT 14:00-17:00"], 1, "FRI") == "SAT";
}

test "buying everything in store breaks the 6 kg limit" {
    cands = evaluated(demo_profile());
    all_store = [c for c in cands if c.channels == ["kroger-store"]][0];
    assert all_store.carried_kg > 6.0;
    assert not all_store.feasible();
    assert any(["kg" in v for v in all_store.violations]);
}

test "a small delivery basket under the minimum order is rejected" {
    cands = evaluated(demo_profile());
    rice_only = [
        c for c in cands
        if c.channels == ["kroger-delivery", "kroger-store"]
        and c.assignment["rice"].channel == "kroger-delivery"
        and c.assignment["detergent"].channel == "kroger-store"
        and c.assignment["milk"].channel == "kroger-store"
        and c.assignment["eggs"].channel == "kroger-store"
    ][0];
    assert any(["minimum order" in v for v in rice_only.violations]);
}

test "with free time, options are distinct, feasible, and cost-first is the cheapest" {
    p = demo_profile();
    p.time_value_per_hour = 0.0;
    cands = evaluated(p);
    opts = select_options(cands);
    assert 1 <= len(opts) <= 3;
    cheapest = min([c.cost.total() for c in cands if c.feasible()]);
    for c in opts {
        assert c.feasible() and c.carried_kg <= 6.0;
        if "COST_FIRST" in c.labels {
            assert c.cost.total() == cheapest;
        }
    }
    labels = [];
    for c in opts {
        labels += c.labels;
    }
    assert sorted(labels) == ["BALANCED", "CONVENIENCE_FIRST", "COST_FIRST"];
}

test "time value defaults to $25/h and a trip can override it" {
    p = UserProfile();
    assert effective_constraints(p, None)["time_value"] == 25.0;
    assert effective_constraints(p, TripConstraints(time_value_per_hour=0.0))["time_value"] == 0.0;
    assert p.time_value_per_hour == 25.0;
}

test "active time is priced at the user's time value" {
    cands = evaluated(demo_profile());
    bus_trip = [c for c in cands if c.channels == ["kroger-store"]][0];
    assert bus_trip.active_min == 70;
    assert bus_trip.time_cost == 29.17;              # 70 min at $25/h
    assert bus_trip.effective_cost() == round(bus_trip.cost.total() + 29.17, 2);
}

"""Milk only: a $6.70 bus trip (70 min) or a $17.75 delivery (10 min)."""
def balanced_kind(time_value: float) -> str {
    chans = by_id([
        Channel(id="store", store="Kroger", kind="IN_STORE", mode="BUS", travel_min=50, shop_min=20,
                transport_cost=3.0, windows=["SAT 07:00-23:00"]),
        Channel(id="delivery", store="Kroger", kind="DELIVERY", delivery_fee=7.99, service_fee_pct=0.05,
                tip=5.0, windows=["SAT 14:00-17:00"], ready_day="FRI")
    ]);
    quotes = [
        Quote(need="milk", channel="store", price=3.49, weight_kg=2.0),
        Quote(need="milk", channel="delivery", price=4.29, weight_kg=2.0)
    ];
    p = UserProfile(transport=["BUS"], weekly_budget=60.0, free_windows=["SAT 14:00-17:00"],
                    time_value_per_hour=time_value);
    ctx = effective_constraints(p, None);
    needs = [Need(key="milk")];
    cands = build_candidates(needs, chans, quotes);
    for c in cands {
        evaluate(c, by_key(needs), chans, ctx, []);
    }
    best = [c for c in select_options(cands) if "BALANCED" in c.labels][0];
    return chans[best.channels[0]].kind;
}

test "the trip wins only when its savings beat the user's time value" {
    # the bus trip saves about $11 for 60 extra minutes, i.e. about $11/h
    assert balanced_kind(0.0) == "IN_STORE";
    assert balanced_kind(5.0) == "IN_STORE";
    assert balanced_kind(25.0) == "DELIVERY";
}

test "a plan that saves 3 cents for 25 more minutes is not recommended" {
    opts = select_options(evaluated(demo_profile()));          # $25/h
    assert not [c for c in opts if "corner-store" in c.channels];
    cost_pick = [c for c in opts if "COST_FIRST" in c.labels][0];
    assert cost_pick.channels == ["kroger-delivery"];
    assert "$0.03 cheaper takes 25 more min" in cost_pick.skipped;
}

test "with free time the cheapest plan is kept and nothing is skipped" {
    p = demo_profile();
    p.time_value_per_hour = 0.0;
    opts = select_options(evaluated(p));
    cost_pick = [c for c in opts if "COST_FIRST" in c.labels][0];
    assert "corner-store" in cost_pick.channels and cost_pick.skipped == "";
}

test "the fastest plan always survives the time rule" {
    cands = [c for c in evaluated(demo_profile()) if c.feasible()];
    fastest = sorted(cands, key=lambda c: Candidate : c.active_min)[0];
    assert fastest in worth_the_time(cands);
}

