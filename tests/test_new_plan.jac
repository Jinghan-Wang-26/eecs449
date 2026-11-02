"""New-list boundaries use detached graphs and synthetic stores; no network/model."""
import uuid;
import from unittest.mock { patch }
import from tests.test_visits { STORE, TRAVEL, evidence }
import from harness.agent { handle_request }
import from ai.intents { validate_intent }
import from app_settings { stamp }
import from server.workflows { start_new_plan, save_need, workspace_view }
import from server.shopping { shopping_operation }
import from server.visits { visit_action, visit_context }
import from server.chat { saved_history }
import from models.profile { UserProfile }
import from models.interest { InterestKind, InterestStatus, InterestPool }
import from models.events { ShoppingWorkspace }
import from models.plan { ShoppingPlan, PlanStatus }
import from models.graph { owned, items_of, Owns, plans_of }
import from planning.visits { candidate }

glob WHEN: str = "2030-01-01T10:00:00-05:00";

def visit_user() -> UserProfile {
    p = UserProfile(data_mode="live", transport=["WALK"], weekly_budget=50, free_windows=["SAT 14:00-17:00"]);
    p +>:Owns:+> InterestPool();
    p.location = {"id":"origin", "address":"Synthetic address", "lat":42, "lon":-83};
    shopping_operation(p, "save_interest", {"category":"rice", "qty":2}, WHEN);
    with patch("planning.visits.route", return_value=TRAVEL) {
        plan = candidate(STORE, evidence(), visit_context(p, WHEN), WHEN);
    }
    owned(p, ShoppingWorkspace).visit_plans = [plan];
    return p;
}

def turn(p: UserProfile, text: str, value: dict) -> str {
    with patch("harness.agent.parse_request", return_value=validate_intent(value)) {
        return handle_request(p, text, []);
    }
}

def result_fixture(p: UserProfile) -> dict {
    with patch("planning.visits.route", return_value=TRAVEL) {
        plan = candidate(STORE, evidence(), visit_context(p, stamp()), stamp());
    }
    return {"plans":[plan], "stores":[STORE], "notices":[], "generated_at":WHEN,"checked_stores":1,"nearby_count":1};
}


test "new plan clears active list and pending conversation but preserves profile and old purchase history" {
    p = visit_user(); p.weekly_budget = 77; p.home_address = "Synthetic saved address";
    state = owned(p, ShoppingWorkspace); plan = state.visit_plans[0];
    import from planning.visits { signature }
    plan["input_signature"] = signature(visit_context(p, WHEN));
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PARTIAL", "bought_qty":1, "actual_paid":3}, WHEN);
    state.chat_address_pending = True; state.chat_question = "Pick an old address";
    state.address_candidates = [{"id":"stale"}]; state.pending_id = "stale";
    state.pending_intent = {"intent":"feedback"}; state.chat_messages = [{"role":"user", "content":"old request"}];
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    assert not [n for n in items_of(p) if n.plannable()];
    assert p.home_address == "Synthetic saved address" and p.weekly_budget == 77 and p.transport == ["WALK"];
    assert state.visit_plans == [] and state.visit_history[0]["items"][0]["actual_paid"] == 3;
    assert state.visit_history[0]["status"] == "COMPLETED";
    assert state.chat_planning and not state.chat_address_pending and state.pending_id == "" and state.address_candidates == [];
    assert len(saved_history(p)) == 1 and "new trip" in state.chat_question;
    assert items_of(p)[0].status == InterestStatus.PAUSED and not items_of(p)[0].in_current_list;
    assert workspace_view(p, WHEN)["visit_history"][0]["items"][0]["remaining_qty"] == 1;
}

test "accepted old visit cannot block accepting a plan after starting a new list" {
    p = visit_user(); state = owned(p, ShoppingWorkspace); old = state.visit_plans[0];
    visit_action(p, {"key":old["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    assert old["status"] == "CANCELLED" and state.visit_history[0]["key"] == old["key"];
    shopping_operation(p, "save_interest", {"category":"milk","qty":1}, WHEN);
    with patch("planning.visits.route", return_value=TRAVEL) {
        new = candidate(STORE, evidence([]), visit_context(p, WHEN), WHEN);
    }
    state.visit_plans = [new];
    visit_action(p, {"key":new["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    assert new["status"] == "ACCEPTED" and new["items"][0]["category"] == "milk" and len(new["items"]) == 1;
}

test "adding the same category to a fresh list does not inherit old quantity specifications or snooze" {
    p = visit_user(); n = items_of(p)[0];
    n.product_spec.update({"qty":6, "brand":"Old brand", "size":"5 kg"}); n.snoozed_until = "2040-01-01";
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    n = save_need(p, {"category":"rice"});
    assert n.product_spec["qty"] == 1 and n.product_spec["brand"] == "" and n.product_spec["size"] == "";
    assert n.in_current_list and n.plannable() and n.snoozed_until == "";
    assert len(items_of(p)) == 1;
}

test "old needs can be explicitly restored with their saved specifications" {
    p = visit_user(); n = items_of(p)[0]; n.product_spec["brand"] = "Test";
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    shopping_operation(p, "interest_status", {"category":"rice","status":"ACTIVE"}, WHEN);
    assert n.plannable() and n.product_spec["qty"] == 2 and n.product_spec["brand"] == "Test";
    save_need(p, {"category":"rice","qty":3}); assert n.product_spec["brand"] == "Test";
}

test "restart retries do not wipe new needs and invalid requests do not mutate anything" {
    p = visit_user(); state = owned(p, ShoppingWorkspace); failed = False;
    try { start_new_plan(p, "", WHEN); } except ValueError { failed = True; }
    assert failed and items_of(p)[0].plannable() and len(state.visit_plans) == 1;
    request = str(uuid.uuid4()); start_new_plan(p, request, WHEN);
    save_need(p, {"category":"eggs","qty":2}); start_new_plan(p, request, WHEN);
    assert [n.product_spec["type"] for n in items_of(p) if n.plannable()] == ["eggs"];
}

test "clearing chat is distinct from starting a new plan and other users are isolated" {
    p = visit_user(); other = visit_user();
    saved_history(p, True);
    assert items_of(p)[0].plannable() and len(owned(p, ShoppingWorkspace).visit_plans) == 1;
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    assert items_of(other)[0].plannable() and len(owned(other, ShoppingWorkspace).visit_plans) == 1;
}

test "mock plans and replenishment are paused but watch interests and completed plans remain" {
    p = UserProfile(data_mode="mock"); p +>:Owns:+> InterestPool();
    shopping_operation(p,"save_interest",{"category":"rice","qty":2},WHEN);
    shopping_operation(p,"save_interest",{"category":"milk","kind":"WATCH","target_price":4},WHEN);
    shopping_operation(p,"save_interest",{"category":"eggs","kind":"REPLENISH","replenishment_days":7,"last_purchased_at":"2029-12-20"},WHEN);
    accepted = ShoppingPlan(status=PlanStatus.ACCEPTED); completed = ShoppingPlan(status=PlanStatus.COMPLETED);
    p +>:Owns:+> accepted; p +>:Owns:+> completed;
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    assert accepted.status == PlanStatus.CANCELLED and completed.status == PlanStatus.COMPLETED;
    assert not [n for n in items_of(p) if n.plannable()];
    watch = [n for n in items_of(p) if n.kind == InterestKind.WATCH][0];
    assert watch.status == InterestStatus.ACTIVE and watch.target_price == 4;
}

test "chat after restart uses only the new shopping list and saved profile" {
    p = visit_user(); state = owned(p, ShoppingWorkspace);
    start_new_plan(p, str(uuid.uuid4()), WHEN);
    with patch("server.visits.recommend", side_effect=lambda ctx: dict, now: str: result_fixture(p)) as request {
        reply = turn(p, "Buy two packages of milk for this trip", {"intent":"update","needs":[{"category":"milk","qty":2}]});
        assert request.call_count == 1;
        assert [n["type"] for n in request.call_args.args[0]["needs"]] == ["milk"];
    }
    assert "rice" not in state.visit_plans[0]["items"][0]["category"];
}
