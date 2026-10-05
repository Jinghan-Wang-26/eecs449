"""The chat reaches the model only through an empty harness."""

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
