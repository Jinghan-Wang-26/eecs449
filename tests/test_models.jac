import from models.profile { UserProfile, TripConstraints, effective_constraints }
import from models.interest { InterestItem, InterestKind }
import from models.plan { ShoppingPlan, PlanStatus, ItemOutcome }
import from models.graph { Owns, profile_of, items_of, plans_of, trip_of, add_need, add_plan_item, need_of }

test "profile, pool, and plan connect" {
    p = profile_of(root);
    assert profile_of(root) == p;
    milk = add_need(p, {"type": "milk", "qty": 1});
    assert len(items_of(p)) >= 1 and milk.plannable();
    plan = ShoppingPlan();
    p +>:Owns:+> plan;
    pi = add_plan_item(plan, milk, "IN_STORE");
    pi.outcome = ItemOutcome.PURCHASED;
    assert need_of(pi) == milk and len(plans_of(p)) >= 1;
}

test "trip constraints override without touching the profile" {
    p = UserProfile(weekly_budget=60.0, transport=["BUS"]);
    p +>:Owns:+> TripConstraints(transport=["RIDESHARE"]);
    c = effective_constraints(p, trip_of(p));
    assert c["transport"] == ["RIDESHARE"] and c["budget"] == 60.0 and p.transport == ["BUS"];
}

test "locked fields reject learned updates" {
    p = UserProfile(locked=["carry_limit_kg"]);
    assert not p.learn("carry_limit_kg", 10.0);
    assert p.carry_limit_kg == 6.0;
}

test "plan state machine rejects skipped states" {
    plan = ShoppingPlan();
    assert not plan.move_to(PlanStatus.COMPLETED);
    assert plan.move_to(PlanStatus.PROPOSED) and plan.move_to(PlanStatus.ACCEPTED);
    assert plan.move_to(PlanStatus.NEEDS_REVIEW);
}

test "discover items stay out of planning" {
    assert not InterestItem(product_spec={"type": "yogurt"}, kind=InterestKind.DISCOVER).plannable();
}
