"""Detached graph tests with explicitly synthetic store and route records."""
import from unittest.mock { patch }
import from app_settings { stamp }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.catalog { Offer }
import from models.events { ShoppingWorkspace }
import from models.graph { Owns, Has, owned, items_of, catalog_of }
import from server.shopping { shopping_operation }
import from server.workflows { workflow }
import from server.visits { visit_context, visit_action, visit_view, recommend_visits }
import from planning.visits { candidate }
import from tests.test_visits { STORE, TRAVEL, evidence }

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

test "visit acceptance requires acknowledgment and never creates current offers" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0]; failed = False;
    try { visit_action(p, {"key":plan["key"], "action":"accept"}, WHEN); }
    except ValueError { failed = True; }
    assert failed;
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    assert plan["status"] == "ACCEPTED" and len(items_of(p)) == 1;
    cat = catalog_of(p);
    assert [cat ->:Has:->][?:Offer] == [];
}

test "bought items update needs and complete a visit without mutating provider evidence" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PURCHASED"}, WHEN);
    assert plan["status"] == "COMPLETED";
    assert not [n for n in items_of(p) if n.plannable()];
    assert plan["items"][0]["evidence"]["price"] == 3;
    assert visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PURCHASED"}, WHEN) == "Outcome already recorded.";
}

test "not found leaves the need active for a later store" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"NOT_FOUND"}, WHEN);
    assert plan["status"] == "COMPLETED" and items_of(p)[0].plannable();
}

test "changed constraints invalidate accepted visits and block old outcomes" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    shopping_operation(p, "update_profile", {"weekly_budget":20}, WHEN);
    assert plan["status"] == "NEEDS_REVIEW";
    failed = False;
    try { visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PURCHASED"}, WHEN); }
    except ValueError { failed = True; }
    assert failed and items_of(p)[0].plannable();
}

test "expired routes prevent new acceptance but allow already accepted visit reporting" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0]; failed = False;
    try { visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, "2030-01-01T12:00:00-05:00"); }
    except ValueError { failed = True; }
    assert failed;
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    visit_action(p, {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PURCHASED"}, "2030-01-01T12:00:00-05:00");
    assert plan["status"] == "COMPLETED";
}

test "address changes hide old proposals and mode switches isolate visits" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0]; state = owned(p, ShoppingWorkspace);
    state.address_candidates = [{"id":"new", "address":"Other synthetic address", "lat":43, "lon":-83}];
    workflow(p, "confirm_address", {"id":"new"}, WHEN);
    assert plan["status"] == "CANCELLED" and visit_view(p, WHEN) == [];
    workflow(p, "set_mode", {"mode":"mock"}, WHEN);
    assert visit_view(p, WHEN) == [];
}

test "live plan action invokes real visit recommender without requiring Kroger or tax" {
    p = visit_user(); state = owned(p, ShoppingWorkspace);
    result = {"plans": [], "stores": [], "notices": ["No local historical coverage"], "generated_at":WHEN, "checked_stores":0, "nearby_count":0};
    with patch("server.visits.recommend", return_value=result) as request {
        workflow(p, "plan", {}, WHEN);
        assert request.call_count == 1;
    }
    assert state.notices == ["No local historical coverage"];
}

test "partial purchase preserves remainder and specifications and duplicate reporting is idempotent" {
    p = visit_user(); n = items_of(p)[0];
    n.product_spec["brand"] = "Test"; n.product_spec["size"] = "1 kg";
    state = owned(p, ShoppingWorkspace); plan = state.visit_plans[0];
    import from planning.visits { signature }
    plan["input_signature"] = signature(visit_context(p, WHEN));
    visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    outcome = {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PARTIAL", "bought_qty":1, "actual_paid":"3.25"};
    visit_action(p, outcome, WHEN);
    assert plan["status"] == "COMPLETED" and n.plannable();
    assert n.product_spec["qty"] == 1 and n.product_spec["brand"] == "Test" and n.product_spec["size"] == "1 kg";
    visible = shopping_operation(p, "view", {}, WHEN)["interests"][0];
    assert visible["qty"] == 1 and visible["brand"] == "Test" and visible["size"] == "1 kg";
    assert plan["items"][0]["remaining_qty"] == 1 and plan["reported_paid_usd"] == 3.25;
    assert plan["reference_subtotal"] == 6 and plan["items"][0]["evidence"]["price"] == 3;
    assert visit_action(p, outcome, WHEN) == "Outcome already recorded.";
    assert n.product_spec["qty"] == 1;
    changed = dict(outcome); changed["actual_paid"] = "9"; failed = False;
    try { visit_action(p, changed, WHEN); } except ValueError { failed = True; }
    assert failed and plan["reported_paid_usd"] == 3.25;
    with patch("planning.visits.route", return_value=TRAVEL) {
        replacement = candidate(STORE, evidence(), visit_context(p, WHEN), WHEN);
    }
    assert replacement["items"][0]["qty"] == 1;
    with patch("server.visits.recommend", return_value={"plans":[replacement], "stores":[STORE], "notices":[], "generated_at":WHEN,"checked_stores":1,"nearby_count":1}) {
        recommend_visits(p, WHEN);
    }
    visit_action(p, {"key":replacement["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
    visit_action(p, {"key":replacement["key"], "action":"outcome", "category":"rice", "outcome":"PURCHASED"}, WHEN);
    assert not n.plannable() and replacement["status"] == "COMPLETED";
}

test "invalid partial outcomes never change graph or historical prices" {
    for data in [{"bought_qty":0}, {"bought_qty":2}, {"bought_qty":1.5}, {"bought_qty":True}, {"bought_qty":1,"actual_paid":"nan"}, {"bought_qty":1,"actual_paid":-2}] {
        p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
        visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, WHEN);
        value = {"key":plan["key"], "action":"outcome", "category":"rice", "outcome":"PARTIAL"}; value.update(data); failed = False;
        try { visit_action(p, value, WHEN); } except ValueError { failed = True; }
        assert failed and items_of(p)[0].product_spec["qty"] == 2 and plan["items"][0]["outcome"] == "PENDING";
    }
}

test "passed departure prevents acceptance even if route quote remains fresh" {
    p = visit_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    plan["route"]["departure_at"] = "2030-01-01T10:05:00-05:00";
    failed = False;
    try { visit_action(p, {"key":plan["key"], "action":"accept", "acknowledge_unknowns":True}, "2030-01-01T10:06:00-05:00"); }
    except ValueError { failed = True; }
    assert failed and plan["status"] == "NEEDS_REVIEW";
}
