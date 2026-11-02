"""Scheduled background reminder checks for users who opted in.

The Jac scheduler ticks every minute on a daemon thread with no request context.
Each tick opens a request-style context per user root (as the HTTP server does),
runs the same refresh as the panel's Refresh button when that user is due,
emails new reminders to users who opted in, and commits. A concurrent request
that wins a write conflict simply defers the check to the next tick.
"""

import os;
import logging;
import threading;
import from jaclang { JacRuntime as Jac }
import from jaclang.runtimelib.context { ExecutionContext }
import from jaclang.runtimelib.exceptions { WriteConflict }
import from jaclang.jac0core.osp_kernel_sv { isolate_request_walk_stack }
import from app_settings { get_settings, stamp }
import from models.profile { UserProfile }
import from models.graph { reminders_of }
import from notify.background { skip_reason, record_run }
import from notify.delivery { deliver_reminders }
import from server.shopping { shopping_operation }
import from server.workflows { mode_of }

glob logger = logging.getLogger(__name__),
     _tick_lock = threading.Lock();

"""Run one user's check if it is due. Returns the skip reason or a summary."""
def background_tick(p: UserProfile, now: str, settings: dict = {}) -> dict {
    cfg = get_settings(settings);
    cfg["data_mode"] = mode_of(p);
    now = stamp(now, cfg);
    reason = skip_reason(p, now, cfg);
    if reason != "" { return {"ran": False, "reason": reason}; }
    before = len(reminders_of(p));
    error = "";
    try {
        shopping_operation(p, "refresh", {}, now);
    } except ValueError as err {
        error = str(err);
    }
    created = len(reminders_of(p)) - before;
    record_run(p, now, created, error);
    return {"ran": True, "created": created, "error": error};
}

def user_roots -> list[str] {
    um = Jac.get_user_manager(base_path=os.getcwd());
    um._ensure_connection();
    conn = um._conn;
    if conn is None { return []; }
    with um._lock {
        rows = conn.execute("SELECT root_id FROM users").fetchall();
    }
    return [str(row[0]) for row in rows];
}

def check_root(root_id: str, now: str) -> dict {
    ctx = ExecutionContext(_parent=Jac.get_context());
    ctx.set_user_root(root_id);
    token = Jac.push_request_context(ctx);
    isolate_request_walk_stack();
    try {
        # Never create a profile for a root that has not used the workspace.
        found = [Jac.root() -->][?:UserProfile];
        if not found { return {"ran": False, "reason": "no profile"}; }
        result = background_tick(found[0], now);
        # Delivery runs every tick so a failed send retries on its own backoff,
        # not only when the next refresh is due.
        result["delivered"] = deliver_reminders(found[0], now);
        Jac.commit();
        return result;
    } except WriteConflict {
        ctx.mem.abort();
        return {"ran": False, "reason": "write conflict; retry next tick"};
    } except Exception as err {
        ctx.mem.abort();
        logger.exception("Background reminder check failed");
        return {"ran": False, "reason": "error: " + str(err)};
    } finally {
        Jac.reset_request_context(token);
    }
}

"""Scheduler entry point. Per-user intervals come from app.toml at run time."""
@schedule(interval=60.0)
def run_background_reminders -> None {
    # A slow provider refresh must not overlap the next tick.
    if not _tick_lock.acquire(blocking=False) { return; }
    try {
        now = stamp();
        for root_id in user_roots() {
            result = check_root(root_id, now);
            if result["ran"] or result["delivered"] not in [0, "disabled"] {
                logger.info(f"Background reminders for {root_id[:8]}: {result}");
            }
        }
    } finally {
        _tick_lock.release();
    }
}
