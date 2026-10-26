"""Chat session and the walker the page calls."""

import from harness.agent { handle_request }
import from models.graph { profile_of, owned }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from config { SYSTEM_PROMPT }
import from server.llm { chat_complete }
import from harness.pipeline { before_model, after_model }
import from server.workflows { start_new_plan }
import from app_settings { stamp }

def new_session() -> list {
    return [{"role": "system", "content": SYSTEM_PROMPT}];
}

def take_turn(messages: list, user_text: str) -> str {
    messages.append({"role": "user", "content": user_text});
    reply = after_model(chat_complete(before_model(messages)));
    messages.append({"role": "assistant", "content": reply});
    return reply;
}

def saved_history(p: UserProfile, clear: bool = False) -> list {
    state = owned(p, ShoppingWorkspace);
    if clear { state.chat_messages = []; }
    return [dict(turn) for turn in getattr(state, "chat_messages", [])];
}

def send_message(p: UserProfile, text: str) -> str {
    if not isinstance(text, str) or not text.strip() or len(text) > 4000 {
        raise ValueError('Please enter a shopping request of at most 4000 characters.');
    }
    state = owned(p, ShoppingWorkspace);
    history = saved_history(p);
    try { answer = handle_request(p, text, history); }
    except ValueError as err { answer = str(err); }
    state.chat_messages = (history + [{"role":"user", "content":text}, {"role":"assistant", "content":answer}])[-80:];
    return answer;
}

walker:pub ChatHistory {
    has clear: bool = False;
    can load with Root entry { report saved_history(profile_of(here), self.clear); }
}

walker:pub StartShoppingPlan {
    has request_id: str = "";
    can start with Root entry {
        p = profile_of(here);
        try {
            message = start_new_plan(p, self.request_id, stamp());
            report {"messages": saved_history(p), "message":message};
        } except ValueError as err { report {"error":str(err)}; }
    }
}

walker:pub SendMessage {
    has history: list = [],
        text: str = "";

    can reply with Root entry {
        try { report send_message(profile_of(here), self.text); }
        except ValueError as err { report str(err); }
    }
}
