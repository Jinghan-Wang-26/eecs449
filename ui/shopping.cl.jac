"""Small structured shopping panel alongside the existing chat."""

sv import from ..server.shopping { ShoppingAction }
import from .workspace { WorkspacePanel }

def:pub ShoppingPanel -> JsxElement {
    has snapshot: dict = {"interests": [], "discoveries": [], "reminders": [], "quiet": False},
        active_tab: str = "list",
        category: str = "milk",
        kind: str = "NEED",
        quantity: str = "1",
        target: str = "4.50",
        days: str = "7",
        purchased: str = "",
        busy: bool = False,
        notice: str = "Loading your shopping workspace…",
        seen_reminders: list = [],
        reminders_primed: bool = False,
        notify_permission: str = "unsupported",
        error_notice: str = "";

    async def operate(action: str, data: dict) -> None;
    async def save(e: FormEvent) -> None;

    def tab_key(e: any, id: str) -> None {
        tabs = ["list", "plans", "profile"];
        idx = tabs.indexOf(id);
        if e.key == "ArrowRight" { idx = (idx + 1) % 3; }
        elif e.key == "ArrowLeft" { idx = (idx + 2) % 3; }
        elif e.key == "Home" { idx = 0; }
        elif e.key == "End" { idx = 2; }
        else { return; }
        e.preventDefault();
        next_tab = tabs[idx]; active_tab = next_tab;
        document.getElementById("tab-" + next_tab).focus();
    }

    can with [] entry {
        operate("view", {});
        if window.Notification { notify_permission = window.Notification.permission; }
        # Poll so reminders created by the server's background checks appear while the page is open.
        timer = setInterval(lambda { window.dispatchEvent(new(CustomEvent, "shopping-chat-updated")); }, 60000);
        return lambda { clearInterval(timer); };
    }
    can with (snapshot) entry {
        if not snapshot.get("background") { return; }
        keys = [item["key"] for item in snapshot["reminders"]];
        if reminders_primed and notify_permission == "granted" {
            for item in snapshot["reminders"] {
                if not seen_reminders.includes(item["key"]) {
                    new(window.Notification, "CartCompass reminder", {"body": item["message"], "tag": item["key"]});
                }
            }
        }
        seen_reminders = keys;
        reminders_primed = True;
    }

    async def ask_notifications() -> None {
        if not window.Notification { return; }
        notify_permission = await window.Notification.requestPermission();
    }

    def background_status(bg: dict) -> str {
        if not bg.get("enabled") { return "Off. Reminders are only checked when you press Refresh tools."; }
        status = "Checked every " + str(bg["interval_minutes"]) + " minutes while the server is running, even when this page is closed.";
        if bg["last_run_at"] == "" { status += " First check within a minute."; }
        else { status += " Last check " + bg["last_run_at"] + "; next after " + bg["next_check_at"] + "."; }
        if bg["quiet"] { status += " Paused during quiet hours."; }
        if bg["last_error"] != "" { status += " Last error: " + bg["last_error"]; }
        return status;
    }

    def show_reminders() -> None {
        active_tab = "list";
        setTimeout(lambda {
            el = document.getElementById("reminders-details");
            if el { el.open = True; el.scrollIntoView({"block": "start", "behavior": "smooth"}); }
        }, 0);
    }
    can with (snapshot, busy) entry {
        listener = lambda e: any { operate("view", {}); };
        window.addEventListener("shopping-chat-updated", listener);
        return lambda { window.removeEventListener("shopping-chat-updated", listener); };
    }

    return <section className="shopping-panel" aria-label="Shopping workspace">
        <div className="shopping-heading"><h2>Shopping workspace</h2><div className="mode-switch" aria-label="Data source">
            <button aria-pressed={snapshot.get("data_mode", "mock") == "mock"} disabled={busy or snapshot.get("data_mode", "mock") == "mock"} onClick={lambda e: MouseEvent { operate("set_mode", {"mode":"mock"}); }}>Demo data</button>
            <button aria-pressed={snapshot.get("data_mode", "mock") == "live"} disabled={busy or snapshot.get("data_mode", "mock") == "live"} onClick={lambda e: MouseEvent { operate("set_mode", {"mode":"live"}); }}>Real stores</button>
        </div></div>
        {if len(snapshot["reminders"]) > 0 {
            <div className="reminder-banner" role="status"><span>{"🔔 " + str(len(snapshot["reminders"])) + (" reminder" if len(snapshot["reminders"]) == 1 else " reminders") + ": " + snapshot["reminders"][0]["message"]}</span><button type="button" onClick={lambda e: MouseEvent { show_reminders(); }}>View</button></div>
        }}
        <div className="source-note"><strong>{"DEMO · Simulated shopping" if snapshot.get("data_mode", "mock") == "mock" else "REAL STORES · Historical price evidence"}</strong>{"Explore budgets, store comparisons and purchase tracking with fictional prices and stock." if snapshot.get("data_mode", "mock") == "mock" else "Nearby stores use your address. Open Prices coverage varies; today's prices and stock are unknown."}</div>
        <nav className="workspace-tabs" role="tablist" aria-label="Shopping sections">
            {[<button key={tab["id"]} id={"tab-" + tab["id"]} role="tab" tabIndex={0 if active_tab == tab["id"] else -1} onKeyDown={lambda e: any { tab_key(e, tab["id"]); }} aria-selected={active_tab == tab["id"]} aria-controls={"panel-" + tab["id"]} onClick={lambda e: MouseEvent { active_tab = tab["id"]; }}>{tab["label"]}</button> for tab in [{"id":"list","label":"My list"},{"id":"plans","label":"Plans & stores"},{"id":"profile","label":"Preferences"}]]}
        </nav>
        <div className="workspace-content" role="tabpanel" id={"panel-" + active_tab} aria-labelledby={"tab-" + active_tab} tabIndex={0}>
            {if error_notice != "" { <div className="error-banner" role="alert"><span>{error_notice}</span><button type="button" aria-label="Dismiss error" onClick={lambda e: MouseEvent { error_notice = ""; }}>×</button></div> }}
            {if active_tab == "list" {
            <div>
                <div className="list-intro"><div><h3>Your shopping list</h3><p>Add items here or tell your assistant what you need.</p></div><span className="count-pill">{str(len([item for item in snapshot["interests"] if item.get("in_current_list", True)])) + " items"}</span></div>
                {if len([item for item in snapshot["interests"] if item.get("in_current_list", True)]) == 0 { <div className="empty-list"><span className="empty-symbol" aria-hidden="true">＋</span><h3>Room for your next essentials.</h3><p>Your list is empty. Start a conversation with the assistant, or add your first item below.</p></div> }}
                {[<div key={item["category"]} className="interest-row"><div><span className="item-name">{str(item.get("qty", 1)) + " × " + item["category"]}</span><span className="item-meta">{(item["brand"] + " · " if item.get("brand") else "") + (item["size"] + " · " if item.get("size") else "") + item["kind"] + " · " + item["status"]}</span></div><div className="row-actions">
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("interest_status", {"category": item["category"], "status": "ACTIVE" if item["status"] == "PAUSED" else "PAUSED"}); }}>{"Resume" if item["status"] == "PAUSED" else "Pause"}</button>
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("feedback", {"id": crypto.randomUUID(), "type": "feedback", "target": item["category"], "reason": "PURCHASED"}); }}>Purchased</button>
                </div></div> for item in snapshot["interests"] if item.get("in_current_list", True)]}
                <details className="quick-add" open><summary>Add an item</summary>
            <form onSubmit={save}>
                <label>Category <input aria-label="Category" list="categories" value={category} onChange={lambda e: ChangeEvent { category = e.target.value; }} /><datalist id="categories">{[<option key={name} value={name} /> for name in ["milk", "eggs", "rice", "laundry detergent", "paper towels", "yogurt", "dish soap", "tofu", "soy sauce", "coffee"]]}</datalist></label>
                <label>Packages <input aria-label="Packages" type="number" min="1" max="20" required value={quantity} onChange={lambda e: ChangeEvent { quantity = e.target.value; }} /></label>
                <label>Interest <select aria-label="Interest" value={kind} onChange={lambda e: ChangeEvent { kind = e.target.value; }}>
                    <option value="NEED">Need</option><option value="WATCH">Watch price / stock</option><option value="REPLENISH">Replenish</option>
                </select></label>
                {if kind == "WATCH" {
                    <label>Target price ($) <input type="number" min="0.01" step="0.01" required value={target} onChange={lambda e: ChangeEvent { target = e.target.value; }} /></label>
                }}
                {if kind == "REPLENISH" {
                    <label>Every (days) <input type="number" min="1" max="365" required value={days} onChange={lambda e: ChangeEvent { days = e.target.value; }} /></label>
                }}
                {if kind == "REPLENISH" {
                    <label>Last purchased <input type="date" required value={purchased} onChange={lambda e: ChangeEvent { purchased = e.target.value; }} /></label>
                }}
                <button type="submit" disabled={busy}>Save interest</button>
            </form>
            </details>
            {if len([item for item in snapshot["interests"] if not item.get("in_current_list", True)]) > 0 {
                <details>
                    <summary>Previous shopping needs</summary>
                    <p>These needs are paused and excluded from your new plan. Restore only the items you want to carry over.</p>
                    {[<div key={item["category"]}>
                        <span>{str(item["qty"]) + " × " + item["category"] + " · " + item["brand"] + " · " + item["size"]}</span>
                        <button disabled={busy} onClick={lambda e: MouseEvent { operate("interest_status", {"category":item["category"], "status":"ACTIVE"}); }}>Restore to current list</button>
                    </div> for item in snapshot["interests"] if not item.get("in_current_list", True)]}
                </details>
            }}
            <details id="reminders-details" className="secondary-tools"><summary>Discoveries & reminders</summary>
            <h3>Discoveries</h3>
            {if len(snapshot["discoveries"]) == 0 { <p>No new recommendations. Save an interest to get started.</p> }}
            {[<div key={item["key"]} style={{"marginBottom": "10px"}}>
                <strong>{item["name"]}</strong><p>{item["reason"]}</p>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("discovery", {"key": item["key"], "action": "accept"}); }}>Add to shopping needs</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("discovery", {"key": item["key"], "action": "dismiss"}); }}>Not interested</button>
            </div> for item in snapshot["discoveries"]]}
            <h3>Reminders</h3>
            <div className="background-reminders">
                <label><input type="checkbox" checked={snapshot.get("background", {}).get("enabled", False)} disabled={busy} onChange={lambda e: ChangeEvent { operate("background", {"enabled": e.target.checked}); }} /> Check for reminders in the background</label>
                <p>{background_status(snapshot.get("background", {}))}</p>
                {if notify_permission == "default" { <button type="button" onClick={lambda e: MouseEvent { ask_notifications(); }}>Enable desktop notifications</button> }}
                {if notify_permission == "denied" { <p>Desktop notifications are blocked in this browser; reminders still appear here.</p> }}
                {if notify_permission == "granted" { <p>Desktop notifications are on while this page is open.</p> }}
            </div>
            {if snapshot["quiet"] { <p>Quiet hours are active. Refresh after quiet hours to see reminders.</p> }}
            {if not snapshot["quiet"] and len(snapshot["reminders"]) == 0 { <p>No reminders are due from fresh catalog data.</p> }}
            {[<div key={item["key"]} style={{"marginBottom": "10px"}}>
                <p>{item["message"]}</p>
                {if item["kind"] != "PLAN_CHANGE" { <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "add"}); }}>Add to shopping needs</button> }}
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "snooze"}); }}>Snooze</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "ignore"}); }}>Show less often</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "dismiss"}); }}>Dismiss</button>
            </div> for item in snapshot["reminders"]]}
            </details>
            </div>
            }}
            {if active_tab != "list" and snapshot.get("workspace") { <WorkspacePanel key={JSON.stringify(snapshot["workspace"]["profile"])} workspace={snapshot["workspace"]} mode={snapshot["data_mode"]} busy={busy} operate={operate} category={category} view={active_tab} /> }}
        </div>
        <div className="sync-status"><p role="status" aria-live="polite">{notice}</p><button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("refresh", {}); }}>{"Refreshing…" if busy else "Refresh tools"}</button></div>
    </section>;
}
