"""Legacy chat compatibility checks; active intent tests are in test_live_workflow and test_providers."""

import os;

import from server.chat { new_session, take_turn }
import from harness.pipeline { before_model, after_model }

test "harness does not change the conversation or the reply" {
    messages = [{"role": "user", "content": "milk"}];
    assert before_model(messages) == messages;
    assert after_model("ok") == "ok";
}

test "without an api key the chat does not call the network" {
    previous = os.getenv("LLM_API_KEY");
    os.environ["LLM_API_KEY"] = "";
    messages = new_session();
    reply = take_turn(messages, "I need milk");
    if previous is None {
        del os.environ["LLM_API_KEY"];
    } else {
        os.environ["LLM_API_KEY"] = previous;
    }
    assert "LLM_API_KEY" in reply;
}

test "saved chat survives reloading and clearing does not remove shopping preferences" {
    import from unittest.mock { patch }
    import from server.chat { send_message, saved_history }
    import from models.profile { UserProfile }
    import from models.events { ShoppingWorkspace }
    import from models.graph { owned }
    p = UserProfile(data_mode="mock", weekly_budget=75);
    delattr(owned(p, ShoppingWorkspace), "chat_messages");
    assert saved_history(p) == [];
    with patch("server.chat.handle_request", return_value="What time are you free?") as handler {
        send_message(p, "Plan rice");
        send_message(p, "Saturday afternoon");
        assert len(handler.call_args.args[2]) == 2;
    }
    assert len(saved_history(p)) == 4;
    history = saved_history(p); history[0]["content"] = "tampered";
    assert saved_history(p)[0]["content"] == "Plan rice";
    other = UserProfile(data_mode="mock"); assert saved_history(other) == [];
    owned(p, ShoppingWorkspace).chat_question = "What time?";
    assert saved_history(p, True) == [] and p.weekly_budget == 75;
    assert owned(p, ShoppingWorkspace).chat_question == "What time?";
}

test "chat storage is bounded and provider failures remain visible after reload" {
    import from unittest.mock { patch }
    import from server.chat { send_message, saved_history }
    import from models.profile { UserProfile }
    p = UserProfile(data_mode="mock");
    with patch("server.chat.handle_request", return_value="Saved") {
        for i in range(42) { send_message(p, str(i)); }
    }
    assert len(saved_history(p)) == 80 and saved_history(p)[0]["content"] == "2";
    with patch("server.chat.handle_request", side_effect=ValueError("Synthetic provider outage")) {
        assert send_message(p, "Please try") == "Synthetic provider outage";
    }
    assert saved_history(p)[-1]["content"] == "Synthetic provider outage";
    failed = False;
    try { send_message(p, "x" * 4001); } except ValueError { failed = True; }
    assert failed and len(saved_history(p)) == 80;
}
