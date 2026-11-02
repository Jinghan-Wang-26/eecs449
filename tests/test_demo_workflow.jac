"""Clock advancement and unit-price integration, without external services."""
import from app_settings { stamp }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.catalog { Offer, Product }
import from models.events { ShoppingWorkspace, SyncState }
import from models.plan { PlanStatus }
import from models.graph { Owns, catalog_of, find_in, plans_of, owned, items_of }
import from providers.mock { load_mock }
import from server.shopping { shopping_operation }
import from server.workflows { workspace_view }
import from planning.lifecycle { plan_shopping }

def demo_user() -> UserProfile {
    p = UserProfile(data_mode="mock", weekly_budget=80, carry_limit_kg=20, transport=["WALK", "BUS"], free_windows=["SAT 14:00-17:00"]);
    p +>:Owns:+> InterestPool();
    return p;
}

test "UI plans work today and years after the original fixture expires" {
    for now in [stamp(), "2030-01-01T10:00:00-05:00"] {
        p = demo_user();
        shopping_operation(p, "save_interest", {"category": "rice", "qty": 1}, now);
        result = shopping_operation(p, "plan", {}, now);
        assert len(result["workspace"]["plans"]) > 0;
        assert find_in(catalog_of(p), Offer, "huron:rice-jasmine-5lb:IN_STORE").is_fresh(now);
        item = result["workspace"]["plans"][0]["items"][0];
        assert item["unit"] == "kg" and item["package_price"] > 0;
    }
}

test "persisted old mock catalog upgrades without discarding needs" {
    p = demo_user(); load_mock(catalog_of(p));
    now = "2030-01-01T10:00:00-05:00";
    shopping_operation(p, "save_interest", {"category": "milk"}, now);
    result = shopping_operation(p, "view", {}, now);
    assert result["interests"][0]["category"] == "milk";
    assert all([row["observed_at"].startswith("2030-01-01") for row in result["workspace"]["catalog_prices"]]);
    assert len(shopping_operation(p, "plan", {}, now)["workspace"]["plans"]) > 0;
}

test "expired mock quotes still fail freshness without explicit renewal" {
    p = demo_user();
    shopping_operation(p, "save_interest", {"category": "milk"}, "2028-01-01T10:00");
    assert plan_shopping(p, "2028-01-10T10:00")["plans"] == [];
    assert len(shopping_operation(p, "plan", {}, "2028-01-10T10:00")["workspace"]["plans"]) > 0;
}

test "same day refresh is idempotent and user stock feedback survives later refresh" {
    p = demo_user(); now = "2028-01-01T10:00";
    shopping_operation(p, "save_interest", {"category": "milk"}, now);
    shopping_operation(p, "refresh", {}, now);
    receipts = len(owned(p, SyncState).receipts);
    shopping_operation(p, "refresh", {}, "2028-01-01T11:00");
    assert len(owned(p, SyncState).receipts) == receipts;
    view = shopping_operation(p, "plan", {}, now);
    key = view["workspace"]["plans"][0]["key"];
    shopping_operation(p, "plan_action", {"key": key, "action": "accept"}, now);
    shopping_operation(p, "feedback", {"id": "stock", "type": "feedback", "target": "milk", "reason": "OUT_OF_STOCK"}, now);
    shopping_operation(p, "refresh", {}, "2028-02-01T11:00");
    rows = [row for row in workspace_view(p)["catalog_prices"] if find_in(catalog_of(p), Offer, row["key"]).source == "user"];
    assert len(rows) == 1 and rows[0]["availability"] == "OUT";
}

test "unit-price comparison applies only eligible membership and retains unknowns" {
    p = demo_user(); now = "2028-01-01T10:00";
    shopping_operation(p, "view", {}, now);
    key = "bulk:rice-jasmine-20lb:IN_STORE";
    before = [row for row in workspace_view(p)["catalog_prices"] if row["key"] == key][0];
    p.memberships = ["ARBOR_CLUB"];
    after = [row for row in workspace_view(p)["catalog_prices"] if row["key"] == key][0];
    assert before["package_price"] == 24.99 and after["package_price"] == 21.99;
    assert after["unit_price"] < before["unit_price"] and after["member_price_applied"];
    unknown = [row for row in workspace_view(p)["catalog_prices"] if row["key"] == "quick:rice-jasmine-5lb:DELIVERY"][0];
    assert unknown["package_price"] is None and unknown["unit_price"] is None;
}

test "plan unit price uses the agreed snapshot after a quote changes" {
    p = demo_user(); now = "2028-01-01T10:00";
    shopping_operation(p, "save_interest", {"category": "rice"}, now);
    before = shopping_operation(p, "plan", {}, now)["workspace"]["plans"];
    o = find_in(catalog_of(p), Offer, "huron:rice-jasmine-5lb:IN_STORE");
    o.price = 999;
    after = workspace_view(p)["plans"];
    assert [x["items"] for x in before] == [x["items"] for x in after];
}


test "confirmed chat refresh uses the same mock provider as the refresh button" {
    import from ai.intents { validate_intent }
    p = demo_user(); now = "2028-01-01T10:00";
    shopping_operation(p, "view", {}, now);
    state = owned(p, ShoppingWorkspace);
    state.pending_id = "refresh-request";
    state.pending_intent = validate_intent({"intent": "refresh"});
    shopping_operation(p, "confirm_chat", {"id": "refresh-request"}, "2028-01-02T10:00");
    assert find_in(catalog_of(p), Offer, "huron:milk-whole-1gal:IN_STORE").observed_at.startswith("2028-01-02");
}
