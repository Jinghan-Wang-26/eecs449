"""Email due reminders to users who opted in.

Each reminder is emailed at most once. New reminders are combined into one
digest per check. A failing send backs off exponentially (5 minutes doubling to
6 hours) and retries the same undelivered reminders later. Quiet hours deliver
nothing because the inbox is empty then.
"""

import from app_settings { get_settings, stamp, due, later }
import from models.profile { UserProfile }
import from models.events { DeliveryState }
import from typing { cast }
import from models.graph { owned }
import from notify.reminders { inbox }
import from integrations.channels { send_email, channel_status, valid_email, ChannelError }

glob DIGEST_LIMIT: int = 5;

"""Save email preferences. Changing the address forgets its delivery receipts."""
def set_delivery(p: UserProfile, data: dict) -> str {
    state = cast(DeliveryState, owned(p, DeliveryState));
    email = str(data.get("email", state.email) or "").strip();
    enabled = data.get("email_enabled", state.email_enabled) == True;
    if enabled and not valid_email(email) { raise ValueError("Enter a valid email address."); }
    if enabled and not channel_status()["email"] { raise ValueError("Email is not configured on this server. Add SMTP settings to .env and restart."); }
    if email != state.email {
        state.delivered = {};
        state.failure = {};
    }
    state.email = email;
    state.email_enabled = enabled;
    return "Email settings saved.";
}

def digest(cards: list) -> dict {
    shown = cards[:DIGEST_LIMIT];
    lines = ["- " + str(c["message"]) for c in shown];
    if len(cards) > len(shown) { lines.append(f"...and {len(cards) - len(shown)} more in CartCompass."); }
    title = "CartCompass reminder" if len(cards) == 1 else f"CartCompass: {len(cards)} reminders";
    return {"title": title, "body": "\n".join(lines) + "\n\nOpen CartCompass to add, snooze or dismiss."};
}

def record_failure(state: DeliveryState, error: str, now: str, cfg: dict) -> None {
    count: int = int(state.failure.get("count", 0)) + 1;
    wait_minutes: int = min(5 * (2 ** (count - 1)), 360);
    state.failure = {"count": count, "next_retry_at": later(now, wait_minutes / 60.0, cfg), "last_error": error};
}

"""Email undelivered due reminders. Returns the number sent, or a status string."""
def deliver_reminders(p: UserProfile, now: str, settings: dict = {}) -> any {
    cfg = get_settings(settings);
    now = stamp(now, cfg);
    state = cast(DeliveryState, owned(p, DeliveryState));
    if not state.email_enabled { return "disabled"; }
    if state.failure and not due(str(state.failure["next_retry_at"]), now, cfg) { return "waiting to retry"; }
    fresh = [c for c in inbox(p, now, cfg) if c["key"] not in state.delivered];
    if not fresh { return 0; }
    message = digest(fresh);
    try {
        send_email(state.email, message["title"], message["body"]);
    } except ChannelError as err {
        record_failure(state, str(err), now, cfg);
        return "error: " + str(err);
    }
    state.delivered = state.delivered | {c["key"]: now for c in fresh};
    state.failure = {};
    state.last_delivery = {"at": now, "count": len(fresh)};
    return len(fresh);
}

"""Send one test email now, ignoring backoff, so the user can verify the setup."""
def test_delivery(p: UserProfile) -> str {
    state = cast(DeliveryState, owned(p, DeliveryState));
    if state.email == "" { raise ValueError("Save an email address first."); }
    try {
        send_email(state.email, "CartCompass test", "Reminder emails from CartCompass will arrive here.");
    } except ChannelError as err {
        raise ValueError(str(err));
    }
    return "Test email sent.";
}

def delivery_view(p: UserProfile) -> dict {
    state = cast(DeliveryState, owned(p, DeliveryState));
    return {"email": state.email, "email_enabled": state.email_enabled,
            "email_available": channel_status()["email"],
            "failure": state.failure, "last_delivery": state.last_delivery};
}
