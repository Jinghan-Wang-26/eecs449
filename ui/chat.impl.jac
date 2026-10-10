"""Send handler for the chat page."""

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
}
