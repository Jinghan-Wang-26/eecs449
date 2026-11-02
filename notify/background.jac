"""Opt-in background reminder schedule: when a user's next unattended check is due."""

import from app_settings { get_settings, stamp, due, later, quiet }
import from models.profile { UserProfile }
import from models.events { BackgroundState }
import from typing { cast }
import from models.graph { owned }

def next_check_at(state: BackgroundState, cfg: dict) -> str {
    if not state.enabled { return ""; }
    if state.last_run_at == "" { return "now"; }
    return later(state.last_run_at, int(cfg["background_check_minutes"]) / 60.0, cfg);
}

"""Why a check should not run now, or "" when it is due."""
def skip_reason(p: UserProfile, now: str, cfg: dict) -> str {
    state = cast(BackgroundState, owned(p, BackgroundState));
    if not state.enabled { return "disabled"; }
    # Quiet hours suppress the inbox anyway; skip provider requests as well.
    if quiet(now, cfg) { return "quiet hours"; }
    if state.last_run_at != "" and not due(next_check_at(state, cfg), now, cfg) { return "not due"; }
    return "";
}

def set_background(p: UserProfile, enabled: bool) -> str {
    state = cast(BackgroundState, owned(p, BackgroundState));
    state.enabled = enabled;
    state.last_error = "";
    if not enabled { return "Background reminders turned off."; }
    # Run on the next scheduler tick instead of waiting a full interval.
    state.last_run_at = "";
    return "Background reminders turned on.";
}

def record_run(p: UserProfile, now: str, created: int, error: str) -> None {
    state = cast(BackgroundState, owned(p, BackgroundState));
    state.last_run_at = now;
    state.last_created = created;
    state.last_error = error;
    state.runs += 1;
}

def background_view(p: UserProfile, now: str, settings: dict = {}) -> dict {
    cfg = get_settings(settings);
    state = cast(BackgroundState, owned(p, BackgroundState));
    return {"enabled": state.enabled, "interval_minutes": cfg["background_check_minutes"],
            "last_run_at": state.last_run_at, "next_check_at": next_check_at(state, cfg),
            "last_created": state.last_created, "last_error": state.last_error,
            "runs": state.runs, "quiet": quiet(stamp(now, cfg), cfg)};
}
