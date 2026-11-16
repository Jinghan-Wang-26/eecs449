"""English clarification output without changing source addresses or user input."""
import from unittest.mock { patch }
import from ai.intents { parse_request, validate_intent }
import from ai.language { contains_cjk, ENGLISH_POLICY }
import from models.profile { UserProfile }
import from models.graph { Owns }
import from models.interest { InterestPool }
import from server.chat { send_message, saved_history }

test "CJK model questions use English while validated shopping updates survive" {
    for text in ["\u8bf7\u63d0\u4f9b\u9884\u7b97", "Budget? \u9810\u7b97", "\U00020000", "\uff8a"] {
        result = validate_intent({"intent": "update", "question": text, "profile": {"weekly_budget": 75}});
        assert not contains_cjk(result["question"]);
        assert "clarify" in result["question"];
        assert result["profile"]["weekly_budget"] == 75;
    }
    english = "What's your budget? Caf\u00e9 items are fine, too.";
    assert validate_intent({"intent": "update", "question": english})["question"] == english;
}

test "English policy reaches extraction while source addresses and proper brands remain intact" {
    address = "123 \u4e2d\u6587 Street";
    brand = "\u54c1\u724c";
    with patch("ai.intents.complete_json", return_value={"intent":"update", "address":address, "needs":[{"category":"rice", "brand":brand}]}) as model {
        result = parse_request("\u4e70\u7c73", [{"role":"assistant", "content":"\u4f60\u597d"}]);
        assert ENGLISH_POLICY in model.call_args.args[0][0]["content"];
        assert model.call_args.args[0][-1]["content"] == "\u4e70\u7c73";
        assert result["address"] == address and result["needs"][0]["brand"] == brand;
    }
}

test "English clarification and saved changes persist without rewriting user messages" {
    p = UserProfile(data_mode="live");
    p +>:Owns:+> InterestPool();
    with patch("ai.intents.complete_json", return_value={"intent":"update", "question":"\u8bf7\u63d0\u4f9b\u5730\u5740", "profile":{"weekly_budget":75}}) {
        answer = send_message(p, "\u9884\u7b97 75");
    }
    assert p.weekly_budget == 75 and "75" in answer;
    assert not contains_cjk(answer);
    history = saved_history(p);
    assert history[-1]["content"] == answer;
    assert history[-2]["content"] == "\u9884\u7b97 75";
}
