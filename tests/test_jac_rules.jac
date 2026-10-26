"""Regression coverage for the business rules migrated from Python to Jac."""
import from ai.conversation { saved_message, plan_summary }
import from integrations.validation { number, strings, profile_patch, need_spec }
import from pricing { price_details }

test "English save confirmations retain fields and needs for legacy language preferences" {
    proposal = {"profile":{"weekly_budget":50},"needs":[{"type":"rice","qty":2}]};
    for lang in ["zh", "en"] {
        reply = saved_message(proposal, lang);
        assert "50" in reply and "2 × rice" in reply;
        assert reply.endswith(".\n");
    }
    assert saved_message({"profile":{},"needs":[]}, "zh") == "";
}

test "empty plan results preserve provider notices for legacy language preferences" {
    for lang in ["zh", "en"] {
        assert plan_summary({"visit_plans":[],"notices":["Synthetic provider outage"]}, lang) == "Synthetic provider outage";
    }
}

test "historical summaries retain coverage and distinguish unknown from zero" {
    plan = {"status":"PROPOSED", "accept_allowed":True, "store":{"name":"Synthetic store","address":"Test address"},
        "items":[{"qty":1,"category":"rice"}],"route":None,"matched":1,"need_count":1,
        "reference_subtotal":0,"blockers":[],"route_notices":[]};
    for lang in ["zh", "en"] {
        reply = plan_summary({"visit_plans":[plan]},lang);
        assert "1/1" in reply and "USD 0" in reply and "Synthetic store" in reply;
    }
    plan["reference_subtotal"] = None;
    assert "price unknown" in plan_summary({"visit_plans":[plan]},"zh");
}

test "invalid numeric inputs keep actionable ValueError rather than runtime errors" {
    for value in [None, "not a number", [], {}, True] {
        failed = False;
        try { number(value, 0, 100, "budget"); }
        except ValueError as err { failed = True; assert str(err) == "budget must be a number."; }
        assert failed;
    }
    assert number("25",0,100,"budget") == 25;
}

test "profile normalization and need validation work through Jac imports" {
    assert strings([" WALK ","WALK"],"transport") == ["WALK"];
    assert profile_patch({"transport":[" WALK ","WALK"]}) == {"transport":["WALK"]};
    assert need_spec({"category":" RICE ","qty":"2"})["type"] == "rice";
    failed = False;
    try { profile_patch({"free_windows":["SAT 25:00-26:00"]}); }
    except ValueError as err { failed = True; assert str(err) == "Invalid time window."; }
    assert failed;
}

test "Jac unit prices retain currency labels and unknown size handling" {
    assert price_details(3, label="500 g")["unit_price"] == 6;
    assert price_details(3, label="500 ML")["unit"] == "L";
    assert price_details(0,1,"kg")["price_label"] == "$0.00 / package";
    assert price_details(5,label="2 x 500 g")["unit_price"] is None;
}
