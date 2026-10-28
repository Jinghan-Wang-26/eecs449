"""Send handler for the chat page."""

impl ChatApp.new_plan() -> None {
    if pending { return; }
    pending = True;
    try {
        result = root spawn StartShoppingPlan(request_id=crypto.randomUUID());
        if result.reports and len(result.reports) > 0 {
            payload = result.reports[0];
            if payload.get("error") { history_notice = payload["error"]; }
            else {
                messages = payload["messages"]; draft = ""; history_notice = "";
                workspace_epoch = workspace_epoch + 1;
            }
        } else { history_notice = "Could not start a new shopping plan. Please retry."; }
    } except Exception {
        history_notice = "Could not start a new shopping plan. Please retry.";
    }
    pending = False;
}

impl ChatApp.history(clear: bool = False) -> None {
    pending = True;
    try {
        result = root spawn ChatHistory(clear=clear);
        if result.reports and len(result.reports) > 0 {
            messages = result.reports[0]; history_notice = "";
        } else { history_notice = "Chat history could not be loaded. Refresh to try again."; }
    } except Exception {
        history_notice = "Chat history could not be loaded. Refresh to try again.";
    }
    pending = False;
}

impl ChatApp.send(e: FormEvent) -> None {
    e.preventDefault();
    text = draft.strip();
    if text == "" or pending {
        return;
    }
    prior = messages;
    pending = True;
    draft = "";
    messages = prior + [{"role": "user", "content": text}];
    answer = "No reply came back from the server.";
    try {
        result = root spawn SendMessage(history=prior, text=text);
        reported = result.reports;
        if reported and len(reported) > 0 {
            answer = str(reported[0]);
        }
    } except Exception as err {
        answer = "The chat request failed. " + str(err);
    }
    messages = prior + [
        {"role": "user", "content": text},
        {"role": "assistant", "content": answer}
    ];
    pending = False;
    event = document.createEvent("Event");
    event.initEvent("shopping-chat-updated", False, False);
    window.dispatchEvent(event);
}
