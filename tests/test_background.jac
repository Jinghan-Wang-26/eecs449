import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.events { BackgroundState }
import from models.graph { Owns, owned, reminders_of }
import from server.shopping { shopping_operation }
import from server.background { background_tick, run_background_reminders }

glob NOW: str = "2026-10-12T10:00:00-04:00";

def user() -> UserProfile {
    p = UserProfile(data_mode="mock", transport=["WALK", "BUS"], free_windows=["SAT 14:00-17:00"], weekly_budget=100);
    p +>:Owns:+> InterestPool();
    shopping_operation(p, "save_interest", {"category": "milk", "kind": "REPLENISH",
        "replenishment_days": "7", "last_purchased_at": "2026-10-01"}, NOW);
    return p;
}

test "background checks are opt-in" {
    p = user();
    before = len(reminders_of(p));
    assert background_tick(p, NOW) == {"ran": False, "reason": "disabled"};
    assert len(reminders_of(p)) == before;
    view = shopping_operation(p, "view", {}, NOW)["background"];
    assert not view["enabled"] and view["next_check_at"] == "" and view["interval_minutes"] == 30;
}

test "enabling runs on the next tick and then waits for the interval" {
    p = user();
    p2 = user();
    out = shopping_operation(p, "background", {"enabled": True}, NOW);
    assert out["message"] == "Background reminders turned on." and out["background"]["next_check_at"] == "now";
    first = background_tick(p, NOW);
    assert first["ran"] and first["error"] == "";
    state = owned(p, BackgroundState);
    assert state.runs == 1 and state.last_run_at == NOW;
    assert background_tick(p, "2026-10-12T10:20:00-04:00") == {"ran": False, "reason": "not due"};
    assert background_tick(p, "2026-10-12T10:30:00-04:00")["ran"];
    assert state.runs == 2;
    # Reminders are deduplicated across unattended runs.
    assert background_tick(p, "2026-10-12T11:00:00-04:00")["created"] == 0;
    assert background_tick(p2, NOW)["reason"] == "disabled";
}

test "an unattended run creates a reminder that becomes due later" {
    p = UserProfile(data_mode="mock", transport=["WALK"], free_windows=["SAT 14:00-17:00"], weekly_budget=100);
    p +>:Owns:+> InterestPool();
    shopping_operation(p, "save_interest", {"category": "eggs", "kind": "REPLENISH",
        "replenishment_days": "7", "last_purchased_at": "2026-10-08"}, NOW);
    shopping_operation(p, "background", {"enabled": True}, NOW);
    assert background_tick(p, NOW)["created"] == 0;
    later_run = background_tick(p, "2026-10-15T10:00:00-04:00");
    assert later_run["ran"] and later_run["created"] == 1;
    inbox = shopping_operation(p, "view", {}, "2026-10-15T10:01:00-04:00")["reminders"];
    assert [r["kind"] for r in inbox] == ["REPLENISH"];
    assert owned(p, BackgroundState).last_created == 1;
}

test "quiet hours skip provider refreshes and disabling stops checks" {
    p = user();
    shopping_operation(p, "background", {"enabled": True}, NOW);
    assert background_tick(p, "2026-10-12T23:00:00-04:00") == {"ran": False, "reason": "quiet hours"};
    assert owned(p, BackgroundState).runs == 0;
    out = shopping_operation(p, "background", {"enabled": False}, NOW);
    assert out["message"] == "Background reminders turned off." and not out["background"]["enabled"];
    assert background_tick(p, NOW)["reason"] == "disabled";
}

test "the scheduler entry point ticks every minute" {
    # Attached at runtime by the @schedule decorator.
    assert getattr(run_background_reminders, "schedule_spec").interval == 60.0;
}
