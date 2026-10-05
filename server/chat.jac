"""Chat session and the walker the page calls."""

import from config { SYSTEM_PROMPT }
import from server.llm { chat_complete }
import from harness.pipeline { before_model, after_model }

def new_session() -> list {
    return [{"role": "system", "content": SYSTEM_PROMPT}];
}

def take_turn(messages: list, user_text: str) -> str {
    messages.append({"role": "user", "content": user_text});
    reply = after_model(chat_complete(before_model(messages)));
    messages.append({"role": "assistant", "content": reply});
    return reply;
}

walker:pub SendMessage {
    has history: list = [],
        text: str = "";

    can reply with Root entry {
        messages = new_session();
        for turn in self.history {
            messages.append({"role": turn["role"], "content": turn["content"]});
        }
        report take_turn(messages, self.text);
    }
}
