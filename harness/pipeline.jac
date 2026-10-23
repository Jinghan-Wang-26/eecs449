"""Legacy text-chat compatibility hooks. The active shopping UI uses harness/agent.jac."""

def before_model(messages: list) -> list {
    return messages;
}

def after_model(reply: str) -> str {
    return reply;
}
