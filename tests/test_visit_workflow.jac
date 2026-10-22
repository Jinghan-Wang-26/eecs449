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
