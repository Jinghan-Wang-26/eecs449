"""Middle of the agent. Left empty until profile, planning, and tools exist.

Later, before_model should attach saved constraints and tool results.
after_model should record what the turn changed. Neither does that yet.
"""

def before_model(messages: list) -> list {
    return messages;
}

def after_model(reply: str) -> str {
    return reply;
}
