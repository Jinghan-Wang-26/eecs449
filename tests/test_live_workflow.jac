"""Graph integration tests with explicitly synthetic provider records."""
import from app_settings { stamp }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.catalog { Product, Store, Offer }
import from models.events { ShoppingWorkspace }
import from models.plan { PlanStatus }
import from models.graph { Owns, owned, catalog_of, items_of, plans_of, find_in, want }
import from server.shopping { shopping_operation }
import from server.workflows { workflow, save_need, import_results }
import from planning.lifecycle { plan_shopping }
import from ai.intents { validate_intent }

glob NOW: str = "2026-10-12T10:00:00-04:00";

def live_user() -> UserProfile {
    p = UserProfile(data_mode="live", transport=["WALK"], weekly_budget=50,
        free_windows=["SAT 14:00-17:00"], tax_rate=0.06);
    p +>:Owns:+> InterestPool();
    p.location = {"id": "origin", "address": "Synthetic address", "lat": 42, "lon": -83};
    n = save_need(p, {"category": "rice", "qty": 2});
    s = {"id": "kroger:1", "external_id": "1", "name": "Synthetic store", "address": "Test address", "lat": 42, "lon": -83, "hours": {"SAT": "08:00-22:00"}};
    row = {"key": "kroger:111:01", "external_id": "111", "name": "Test rice", "brand": "Test", "size_label": "1 kg", "weight_kg": 1,
        "price": 3, "availability": "IN_STOCK", "observed_at": NOW, "valid_until": "2026-10-12T15:00:00-04:00"};
    import_results(p, s, n, [row]);
    store = find_in(catalog_of(p), Store, "kroger:1");
    store.routes = {"WALK": {"min": 10, "walk_min": 5, "cost": 0, "valid_until": "2026-10-12T15:00:00-04:00"}};
    row["result_id"] = "result"; row["search_term"] = "rice";
    owned(p, ShoppingWorkspace).product_results = [row];
    return p;
}

test "live products require confirmation and isolated catalogs" {
    p = live_user();
    assert plan_shopping(p, NOW)["plans"] == [];
    workflow(p, "confirm_product", {"id": "result"}, NOW);
    result = plan_shopping(p, NOW);
    assert len(result["plans"]) > 0;
    assert result["plans"][0].total == 6.36;
    assert result["plans"][0].carried_kg == 2;
    assert result["plans"][0].mode == "live";
    workflow(p, "set_mode", {"mode": "mock"}, NOW);
    assert catalog_of(p).mode == "mock";
    assert find_in(catalog_of(p), Offer, "kroger:1:kroger:111:01:IN_STORE") is None;
    assert all([x.status == PlanStatus.CANCELLED for x in result["plans"]]);
    workflow(p, "set_mode", {"mode": "live"}, NOW);
    assert catalog_of(p).mode == "live";
}

test "address change drops routes and marks accepted plan for review" {
    p = live_user();
    workflow(p, "confirm_product", {"id": "result"}, NOW);
    plan = plan_shopping(p, NOW)["plans"][0];
    workflow(p, "plan_action", {"key": plan.key, "action": "accept"}, NOW);
    state = owned(p, ShoppingWorkspace);
    state.address_candidates = [{"id": "new", "address": "Other test address", "lat": 43, "lon": -84}];
    workflow(p, "confirm_address", {"id": "new"}, NOW);
    assert plan.status == PlanStatus.NEEDS_REVIEW;
    assert state.product_results == [];
    assert find_in(catalog_of(p), Store, "kroger:1").routes == {};
    assert plan_shopping(p, NOW)["plans"] == [];
}

test "unknown weight dietary evidence and expired offers prevent live use" {
    p = live_user();
    prod = find_in(catalog_of(p), Product, "kroger:111:01");
    prod.weight_known = False;
    workflow(p, "confirm_product", {"id": "result"}, NOW);
    assert plan_shopping(p, NOW)["plans"] == [];
    workflow(p, "confirm_product", {"id": "result", "weight_kg": "1.2"}, NOW);
    assert len(plan_shopping(p, NOW)["plans"]) > 0;
    p.dietary = ["vegan"];
    assert plan_shopping(p, NOW)["plans"] == [];
    p.dietary = [];
    assert plan_shopping(p, "2026-10-13T10:00:00-04:00")["plans"] == [];
}

test "live public sync cannot spoof provider quotes" {
    p = live_user(); failed = False;
    try { shopping_operation(p, "sync", {"events": [{"type": "offer"}]}, NOW); }
    except ValueError { failed = True; }
    assert failed;
}

test "chat confirmation applies needs and profile exactly once" {
    p = UserProfile(data_mode="mock"); p +>:Owns:+> InterestPool(); state = owned(p, ShoppingWorkspace);
    state.pending_id = "proposal-1";
    state.pending_intent = validate_intent({"intent": "update", "profile": {"weekly_budget": 80}, "needs": [{"category": "rice", "qty": 2}]});
    shopping_operation(p, "confirm_chat", {"id": "proposal-1"}, NOW);
    assert p.weekly_budget == 80;
    assert len([n for n in items_of(p) if n.plannable()]) == 1;
    assert state.pending_intent == {};
    failed = False;
    try { shopping_operation(p, "confirm_chat", {"id": "proposal-1"}, NOW); }
    except ValueError { failed = True; }
    assert failed;
}

test "profile edit invalidates proposals and full mock UI lifecycle completes" {
    p = UserProfile(data_mode="mock"); p +>:Owns:+> InterestPool();
    shopping_operation(p, "update_profile", {"weekly_budget": 80, "free_windows": ["SAT 14:00-17:00"], "transport": ["WALK", "BUS"]}, NOW);
    shopping_operation(p, "save_interest", {"category": "rice", "qty": 2}, NOW);
    view = shopping_operation(p, "plan", {}, NOW);
    assert len(view["workspace"]["plans"]) > 0;
    key = view["workspace"]["plans"][0]["key"];
    shopping_operation(p, "plan_action", {"key": key, "action": "accept"}, NOW);
    shopping_operation(p, "feedback", {"id": "purchase-1", "type": "feedback", "target": "rice", "reason": "PURCHASED"}, NOW);
    assert any([plan.status == PlanStatus.COMPLETED for plan in plans_of(p)]);
    assert not [n for n in items_of(p) if n.plannable()];
}

test "switching mode hides discoveries from the other catalog" {
    p = UserProfile(data_mode="mock"); p +>:Owns:+> InterestPool();
    shopping_operation(p, "save_interest", {"category": "yogurt"}, NOW);
    view = shopping_operation(p, "set_mode", {"mode": "live"}, NOW);
    assert view["data_mode"] == "live";
    assert view["discoveries"] == [];
}

test "historical record cannot be confirmed as a current quote" {
    p = live_user(); state = owned(p, ShoppingWorkspace);
    state.historical_prices = {"records": [{"key": "openprices:price:1", "price": 1, "data_kind": "historical"}]};
    failed = False;
    try { workflow(p, "confirm_product", {"id": "openprices:price:1"}, NOW); }
    except ValueError { failed = True; }
    assert failed;
    assert plan_shopping(p, NOW)["plans"] == [];
}

test "expired proposals cannot be accepted" {
    p = live_user();
    workflow(p, "confirm_product", {"id": "result"}, NOW);
    plan = plan_shopping(p, NOW)["plans"][0]; failed = False;
    try { workflow(p, "plan_action", {"key": plan.key, "action": "accept"}, "2026-10-13T10:00:00-04:00"); }
    except ValueError { failed = True; }
    assert failed and plan.status == PlanStatus.PROPOSED;
}

test "validated chat needs save automatically and ask for missing time" {
    import from unittest.mock { patch }
    import from harness.agent { handle_request }
    p = UserProfile(data_mode="mock"); p +>:Owns:+> InterestPool();
    proposal = validate_intent({"intent": "update", "needs": [{"category": "milk", "qty": 2}]});
    with patch("harness.agent.parse_request", return_value=proposal) {
        message = handle_request(p, "I need two packages of milk", []);
    }
    assert "time range" in message;
    assert len([n for n in items_of(p) if n.plannable()]) == 1;
    assert items_of(p)[0].product_spec["qty"] == 2;
    state = owned(p, ShoppingWorkspace);
    assert state.pending_id == "" and state.chat_planning;
}

test "spec changes require renewed product confirmation while quantity edits preserve it" {
    p = live_user(); workflow(p, "confirm_product", {"id":"result"}, NOW);
    assert len(plan_shopping(p, NOW)["plans"]) > 0;
    save_need(p, {"category":"rice", "qty":3});
    assert len(plan_shopping(p, NOW)["plans"]) > 0;
    save_need(p, {"category":"rice", "brand":"Another brand"});
    assert plan_shopping(p, NOW)["plans"] == [];
    assert items_of(p)[0].product_spec["qty"] == 3;
}
