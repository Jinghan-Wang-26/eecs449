"""Synthetic multi-turn conversations; real graph updates, mocked extraction/providers."""
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool, InterestKind }
import from models.events { ShoppingWorkspace }
import from models.graph { Owns, owned, items_of }
import from server.shopping { shopping_operation }
import from harness.agent { handle_request, conversation_context }
import from ai.intents { validate_intent }
import from app_settings { stamp }
import from server.visits { visit_context }
import from planning.visits { candidate }
import from tests.test_visits { STORE, TRAVEL, evidence, context, NOW }

def chat_user() -> UserProfile {
    p = UserProfile(data_mode="live", transport=["BUS"]);
    p +>:Owns:+> InterestPool();
    return p;
}

def turn(p: UserProfile, text: str, value: dict) -> str {
    with patch("harness.agent.parse_request", return_value=validate_intent(value)) {
        return handle_request(p, text, []);
    }
}

def result_fixture(p: UserProfile) -> dict {
    with patch("planning.visits.route", return_value=TRAVEL) {
        plan = candidate(STORE, evidence(), visit_context(p, str(stamp())), str(stamp()));
    }
    return {"plans":[plan],"stores":[STORE],"notices":[],"generated_at":NOW,"checked_stores":1,"nearby_count":1};
}

test "conversation collects needs address transport and time then plans without confirm button" {
    p = chat_user(); state = owned(p, ShoppingWorkspace);
    assert "address" in turn(p, "Give me a plan", {"intent":"plan"});
    assert state.chat_planning and state.pending_id == "";
    turn(p, "Two rice please", {"intent":"update","needs":[{"category":"rice","qty":2}]});
    assert items_of(p)[0].product_spec["qty"] == 2;
    choices = [{"id":"a","address":"Synthetic A","lat":42,"lon":-83,"precision":"building"}, {"id":"b","address":"Synthetic B","lat":42.1,"lon":-83,"precision":"building"}];
    with patch("server.workflows.geocode", return_value=choices) {
        reply = turn(p, "Synthetic city address", {"intent":"update","address":"Synthetic city address"});
    }
    assert "2. Synthetic B" in reply and not p.location;
    reply = turn(p, "2", {"intent":"update","address_choice":2});
    assert p.home_address == "Synthetic B" and "time range" in reply;
    reply = turn(p, "I can walk for 45 minutes", {"intent":"update","profile":{"transport":["WALK"],"max_walk_min":45}});
    assert "time range" in reply and p.max_walk_min == 45;
    with patch("server.visits.recommend", side_effect=lambda ctx: dict, now: str: result_fixture(p)) as search {
        reply = turn(p, "Saturday 2-5pm", {"intent":"update","profile":{"free_windows":["SAT 14:00-17:00"]}});
        assert search.call_count == 1;
    }
    assert "Synthetic supermarket" in reply and "round trip" in reply;
    assert state.pending_id == "" and not state.chat_planning;
    assert state.visit_plans[0]["status"] == "PROPOSED";
    view = shopping_operation(p, "view", {}, NOW);
    assert view["workspace"]["profile"]["free_windows"] == ["SAT 14:00-17:00"];
}

test "unique precise address saves automatically and asks for missing needs" {
    p = chat_user(); state = owned(p, ShoppingWorkspace);
    row = {"id":"a","address":"Synthetic precise address","lat":42,"lon":-83,"precision":"building","confidence":1};
    with patch("server.workflows.geocode", return_value=[row]) {
        reply = turn(p, "Plan from this address", {"intent":"plan","address":"Synthetic precise address"});
    }
    assert p.home_address == row["address"] and not state.chat_address_pending;
    assert "What would you like to buy" in reply;
}

test "failed replacement address never plans from old location" {
    p = chat_user(); p.location = {"id":"old","lat":42,"lon":-83};
    with patch("server.workflows.geocode", side_effect=ValueError("Synthetic geocoder outage")), patch("server.visits.recommend") as search {
        reply = turn(p, "New address and budget", {"intent":"plan","address":"New address","profile":{"weekly_budget":80}});
        assert search.call_count == 0;
    }
    assert p.weekly_budget == 80 and owned(p, ShoppingWorkspace).chat_address_pending;
    assert "outage" in reply;
    reply = turn(p, "Only bus", {"intent":"update","profile":{"transport":["BUS"]}});
    assert "address" in reply and p.location["id"] == "old";
}

test "only bus is preserved while missing availability is collected" {
    p = chat_user(); p.location = {"id":"a","lat":42,"lon":-83};
    with patch("server.visits.recommend") as search {
        reply = turn(p, "Plan rice, only bus", {"intent":"plan","needs":[{"category":"rice","qty":1}]});
        assert search.call_count == 0;
    }
    assert "time range" in reply and p.transport == ["BUS"];
}

test "buying a watched item turns it into a need with its requested specification" {
    p = chat_user();
    shopping_operation(p,"save_interest",{"category":"milk","kind":"WATCH","target_price":5},NOW);
    turn(p,"Buy two Test milk",{"intent":"update","needs":[{"category":"milk","qty":2,"brand":"Test","size":"1 L"}]});
    n=items_of(p)[0];
    assert n.kind == InterestKind.NEED and n.product_spec["qty"] == 2;
    assert n.product_spec["brand"] == "Test" and n.product_spec["size"] == "1 L";
}

test "ordinary profile update saves without unnecessary plan queries" {
    p = chat_user();
    with patch("server.visits.recommend") as search {
        reply = turn(p,"Budget 80",{"intent":"update","profile":{"weekly_budget":80}});
        assert search.call_count == 0;
    }
    assert p.weekly_budget == 80 and "80" in reply;
    assert not owned(p, ShoppingWorkspace).chat_planning;
}

test "feedback remains a proposal while profile and planning are automatic" {
    p = chat_user(); shopping_operation(p,"save_interest",{"category":"rice"},NOW);
    reply = turn(p,"I bought rice",{"intent":"feedback","feedback":{"target":"rice","reason":"PURCHASED"}});
    assert "Confirm changes" in reply and items_of(p)[0].plannable();
    assert owned(p, ShoppingWorkspace).pending_id != "";
}

test "stop clears gathering but leaves saved preferences and plans" {
    p = chat_user(); state = owned(p, ShoppingWorkspace); state.chat_planning=True;
    state.visit_plans=[{"key":"accepted","status":"ACCEPTED"}];
    turn(p,"Stop planning",{"intent":"stop"});
    assert not state.chat_planning and p.transport == ["BUS"];
    assert state.visit_plans[0]["status"] == "ACCEPTED";
}

test "invalid model data does not mutate the profile" {
    p = chat_user(); failed=False;
    try { turn(p,"Bad hours",{"intent":"update","profile":{"free_windows":["SAT 25:00-26:00"]}}); }
    except ValueError { failed=True; }
    assert failed and p.free_windows == [];
}

test "context carries the last question and saved fields for short replies" {
    p=chat_user();state=owned(p,ShoppingWorkspace);state.chat_question="When are you free?";state.chat_planning=True;
    ctx=conversation_context(p);
    assert ctx["current_question"] == "When are you free?" and ctx["planning_requested"];
    assert ctx["free_windows"] == [] and ctx["transport"] == ["BUS"];
    assert ctx["timezone"] == "America/New_York";
}

test "partial chat updates preserve unspecified product constraints and allow explicit clearing" {
    p = chat_user();
    turn(p, "Two Test milk, 1 L", {"intent":"update", "needs":[{"category":"milk","qty":2,"brand":"Test","size":"1 L"}]});
    turn(p, "Change milk quantity to three", {"intent":"update", "needs":[{"category":"milk","qty":3}]});
    n = items_of(p)[0];
    assert n.product_spec["qty"] == 3 and n.product_spec["brand"] == "Test" and n.product_spec["size"] == "1 L";
    turn(p, "Change the brand to Other", {"intent":"update", "needs":[{"category":"milk","brand":"Other"}]});
    assert n.product_spec["qty"] == 3 and n.product_spec["size"] == "1 L" and n.product_spec["brand"] == "Other";
    turn(p, "Any brand is fine", {"intent":"update", "needs":[{"category":"milk","brand":""}]});
    assert n.product_spec["brand"] == "" and n.product_spec["qty"] == 3 and n.product_spec["size"] == "1 L";
    turn(p, "Remove size restriction", {"intent":"update", "needs":[{"category":"milk","size":""}]});
    assert n.product_spec["size"] == "" and n.product_spec["qty"] == 3;
}

test "new needs receive defaults while malformed specifications do not mutate saved needs" {
    p = chat_user();
    turn(p, "Buy rice", {"intent":"update", "needs":[{"category":"rice"}]});
    n = items_of(p)[0]; assert n.product_spec["qty"] == 1 and n.product_spec["brand"] == "";
    for value in [None, 12, ["bad"]] {
        failed = False;
        try { turn(p, "Bad brand", {"intent":"update", "needs":[{"category":"rice","brand":value}]}); }
        except ValueError { failed = True; }
        assert failed and n.product_spec["brand"] == "" and n.product_spec["qty"] == 1;
    }
}


test "complete bus preferences trigger recommendations without requesting another mode" {
    p = chat_user(); p.location = {"id":"a","lat":42.28,"lon":-83.74};
    p.free_windows = ["SAT 14:00-17:00"]; p.max_transfers = 0;
    result = {"plans":[], "stores":[], "notices":["No scheduled return fits this window."], "generated_at":NOW, "checked_stores":0, "nearby_count":0};
    with patch("server.visits.recommend", return_value=result) as search {
        reply = turn(p, "Plan rice, only bus and no transfers", {"intent":"plan","needs":[{"category":"rice","qty":1}]});
        assert search.call_count == 1;
        assert search.call_args[0][0]["profile"]["transport"] == ["BUS"];
        assert search.call_args[0][0]["profile"]["max_transfers"] == 0;
    }
    assert "No scheduled return" in reply and p.transport == ["BUS"];
}

test "a many-variety item is asked about once, staples are not, and any reply continues planning" {
    p = chat_user(); p.location = {"id":"a","lat":42,"lon":-83}; p.free_windows = ["SAT 14:00-17:00"];
    state = owned(p, ShoppingWorkspace);
    with patch("server.visits.recommend") as search {
        reply = turn(p, "I need milk and chips", {"intent":"update","needs":[{"category":"milk"},{"category":"chips"}]});
        assert search.call_count == 0;
    }
    assert "brand, flavor or size you want for chips" in reply and "milk?" not in reply;
    assert state.chat_question == reply.split("\n")[-1] and state.chat_planning;
    turn(p, "Lay's classic, 8 oz", {"intent":"update","needs":[{"category":"chips","brand":"Lay's","variant":"classic","size":"8 oz"}]});
    chips = [n for n in items_of(p) if n.product_spec["type"] == "chips"][0];
    assert chips.product_spec["brand"] == "Lay's" and chips.product_spec["variant"] == "classic" and chips.product_spec["size"] == "8 oz";
    p2 = chat_user(); p2.location = {"id":"a","lat":42,"lon":-83}; p2.free_windows = ["SAT 14:00-17:00"];
    turn(p2, "I need cereal", {"intent":"update","needs":[{"category":"cereal"}]});
    with patch("server.visits.recommend", side_effect=lambda ctx: dict, now: str: result_fixture(p2)) as search {
        reply = turn(p2, "any", {"intent":"update"});
        assert search.call_count == 1;
    }
    assert "flavor" not in reply;
}

test "a stated preference or a staple item skips the variety question" {
    p = chat_user();
    reply = turn(p, "Pringles original chips and two rice", {"intent":"update","needs":[{"category":"chips","brand":"Pringles","variant":"original"},{"category":"rice","qty":2}]});
    assert "flavor or size" not in reply;
}
