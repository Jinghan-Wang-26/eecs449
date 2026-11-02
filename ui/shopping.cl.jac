"""Trip-centred shopping workspace beside the chat: List → Options → Route → Shop,
with Budget and Preferences opened from the top bar."""

sv import from ..server.shopping { ShoppingAction }
import from .workspace { WorkspacePanel }
import from .budget { BudgetPanel }
import from .tripbar { TripBar, StageNav }
import from .interests { InterestStrip }
import from .routeline { RouteStage }
import from .instore { InStore, TripComplete }
import from .planview { facts, recommended, money, kg, carried, item_amount, trip_ends, tally, tally_label, window_label, open_plans, accepted_plans, describe_changes, short_address, clock }

def load_picked() -> dict {
    try {
        saved = window.localStorage.getItem("cartcompass-picked");
        return JSON.parse(saved) if saved else {};
    } except Exception {
        return {};
    }
}

def:pub ShoppingPanel -> JsxElement {
    has snapshot: dict = {"interests": [], "discoveries": [], "reminders": [], "quiet": False},
        stage: str = "",
        view: str = "",
        selected: str = "",
        picked: dict = load_picked(),
        recorded: dict = {},
        locate_now: bool = False,
        toast: dict = {},
        category: str = "",
        quantity: str = "1",
        busy: bool = False,
        notice: str = "Loading your shopping workspace…",
        seen_reminders: list = [],
        reminders_primed: bool = False,
        notify_permission: str = "unsupported",
        error_notice: str = "",
        email: str = "", email_on: bool = False;

    async def operate(action: str, data: dict, source: str = "") -> bool;
    async def save(e: FormEvent) -> None;

    can with [] entry {
        operate("view", {});
        if window.Notification { notify_permission = window.Notification.permission; }
        # Poll so reminders created by the server's background checks appear while the page is open.
        timer = setInterval(lambda { window.dispatchEvent(new(CustomEvent, "shopping-chat-updated")); }, 60000);
        # The top bar opens Budget and Preferences.
        opener = lambda e: any { view = e.detail; };
        window.addEventListener("cartcompass-view", opener);
        return lambda { clearInterval(timer); window.removeEventListener("cartcompass-view", opener); };
    }
    can with (snapshot) entry {
        if not snapshot.get("background", None) { return; }
        keys = [item["key"] for item in snapshot["reminders"]];
        fresh = [item for item in snapshot["reminders"] if not seen_reminders.includes(item["key"])];
        if reminders_primed and len(fresh) > 0 {
            toast = fresh[0];
            if notify_permission == "granted" {
                for item in fresh { new(window.Notification, "CartCompass reminder", {"body": item["message"], "tag": item["key"]}); }
            }
        }
        seen_reminders = keys;
        reminders_primed = True;
    }
    can with (toast.get("key", "")) entry {
        if not toast.get("key", None) { return; }
        timer = setTimeout(lambda { toast = {}; }, 9000);
        return lambda { clearTimeout(timer); };
    }

    # Load saved channel settings into the form when they first arrive or change.
    can with (JSON.stringify(snapshot.get("delivery", {}))) entry {
        saved = snapshot.get("delivery", None);
        if not saved { return; }
        email = saved["email"]; email_on = saved["email_enabled"];
    }

    # CartCompass only plans with real stores. Profiles saved by the old demo mode move over once.
    can with (snapshot.get("data_mode", "")) entry {
        if snapshot.get("workspace", None) and snapshot.get("data_mode", "live") != "live" { operate("set_mode", {"mode": "live"}); }
    }

    def current_items() -> list { return [item for item in snapshot["interests"] if item.get("in_current_list", True)]; }

    def all_plans() -> list {
        ws = snapshot.get("workspace", None);
        if not ws { return []; }
        return ws["visit_plans"];
    }

    def auto_stage() -> str {
        if len(accepted_plans(snapshot)) > 0 { return "shop"; }
        opens = open_plans(snapshot);
        if len([p for p in opens if p["status"] == "NEEDS_REVIEW" and p.get("accepted_at", None)]) > 0 { return "route"; }
        if recorded.get("store", None) { return "shop"; }
        if len(opens) > 0 { return "options"; }
        return "list";
    }

    # Move to the stage the data implies whenever plans appear, are accepted or finish.
    can with (JSON.stringify([[p["key"], p["status"]] for p in all_plans()]) + "|" + str(len(current_items())) + "|" + str(bool(snapshot.get("workspace", None)))) entry {
        if not snapshot.get("workspace", None) { return; }
        stage = auto_stage();
    }

    def route_plan() -> any {
        opens = open_plans(snapshot);
        for plan in opens { if plan["key"] == selected { return plan; } }
        review = [plan for plan in opens if plan["status"] == "NEEDS_REVIEW" and plan.get("accepted_at", None)];
        if len(review) > 0 { return review[0]; }
        best = recommended([facts(plan) for plan in opens]);
        return best["plan"] if best else None;
    }

    def go(next_stage: str) -> None { stage = next_stage; view = ""; }

    def find_plan(key: str) -> any {
        for plan in all_plans() { if plan["key"] == key { return plan; } }
        return None;
    }

    def select(key: str) -> None { selected = key; stage = "route"; view = ""; }

    def toggle_pick(key: str) -> None {
        updated = JSON.parse(JSON.stringify(picked));
        updated[key] = not updated.get(key, False);
        picked = updated;
        try { window.localStorage.setItem("cartcompass-picked", JSON.stringify(updated)); } except Exception { notice = "Basket ticks are kept only until this page reloads."; }
    }

    def finished(summary: dict) -> None {
        recorded = summary;
        updated = {};
        for key in Object.keys(picked) { if not key.startsWith(summary["plan"] + "|") { updated[key] = picked[key]; } }
        picked = updated;
        try { window.localStorage.setItem("cartcompass-picked", JSON.stringify(updated)); } except Exception { notice = ""; }
    }

    async def find_options() -> None {
        ws = snapshot.get("workspace", None);
        if ws and ws["profile"]["address"] { await operate("recommend_visits", {}); }
        else { locate_now = True; }
        go("options");
    }

    """The one or two things the user would most likely do next, shown as buttons in the chat."""
    def next_actions() -> list {
        ws = snapshot.get("workspace", None);
        if not ws { return []; }
        out = [];
        if ws["pending_id"] != "" { out.append({"id": "go:" + (stage or "list"), "label": "Review the assistant's change"}); }
        accepted = accepted_plans(snapshot);
        opens = open_plans(snapshot);
        items = current_items();
        if len(accepted) > 0 {
            out.append({"id": "go:shop", "label": "Open my in-store list"});
        } elif recorded.get("store", None) {
            out.append({"id": "view:budget", "label": "See my budget"});
        } elif len([p for p in opens if p["status"] == "NEEDS_REVIEW" and p.get("accepted_at", None)]) > 0 {
            out.append({"id": "go:route", "label": "Review what changed"});
        } elif len(opens) > 0 and stage == "route" and route_plan() {
            out.append({"id": "scroll:accept", "label": "Review and accept this plan"});
            if len(opens) > 1 { out.append({"id": "go:options", "label": "See the other options"}); }
        } elif len(opens) > 0 {
            best = recommended([facts(p) for p in opens]);
            if best { out.append({"id": "pick:" + best["key"], "label": "Use " + best["title"]}); }
            if len(opens) > 1 { out.append({"id": "go:options", "label": "Compare all " + str(len(opens)) + " options"}); }
        } elif len(items) > 0 {
            if not ws["profile"]["address"] { out.append({"id": "locate", "label": "Use my current location"}); }
            elif len(ws["profile"]["free_windows"]) == 0 { out.append({"id": "view:profile", "label": "Set when I'm free"}); }
            else { out.append({"id": "find", "label": "Find shopping options"}); }
            out.append({"id": "go:list", "label": "Check my list"});
        }
        return out.slice(0, 3);
    }

    def run_action(code: str) -> None {
        parts = code.split(":");
        if parts[0] == "find" { find_options(); }
        elif parts[0] == "locate" { locate_now = True; go("options"); }
        elif parts[0] == "go" { go(parts[1]); }
        elif parts[0] == "pick" { select(code.slice(5)); }
        elif parts[0] == "view" { view = parts[1]; }
        elif parts[0] == "scroll" {
            go("route");
            setTimeout(lambda {
                panel = document.getElementById("stage-panel");
                if panel { panel.scrollTo({"top": panel.scrollHeight, "behavior": "smooth"}); }
                spot = document.querySelector(".accept-panel input, .accept-panel button.go, .route-accept button.go");
                if spot { spot.scrollIntoView({"block": "center", "behavior": "smooth"}); spot.focus({"preventScroll": True}); }
            }, 120);
        }
    }

    """Tell the chat whether there is anything to show yet and what the next steps are."""
    def publish() -> None {
        ws = snapshot.get("workspace", None);
        info = {"ready": bool(ws),
            "empty": len(current_items()) == 0 and len(all_plans()) == 0 and not recorded.get("store", None) and not (ws and ws["pending_id"] != ""),
            "actions": next_actions()};
        window.dispatchEvent(new(CustomEvent, "workspace-summary", {"detail": info}));
    }

    can with (snapshot, stage, view, recorded, selected, busy) entry {
        publish();
        asked = lambda e: any { publish(); };
        acted = lambda e: any { run_action(e.detail); };
        window.addEventListener("workspace-summary-request", asked);
        window.addEventListener("cartcompass-action", acted);
        return lambda { window.removeEventListener("workspace-summary-request", asked); window.removeEventListener("cartcompass-action", acted); };
    }

    """After the start address is confirmed from the Options step, compare stores right away."""
    async def after_address() -> None {
        locate_now = False;
        if len(current_items()) > 0 { await operate("recommend_visits", {}); }
    }

    def delivery_status(saved: dict) -> str {
        if saved["failure"].get("last_error", None) { return "Last attempt failed: " + saved["failure"]["last_error"] + " Retrying after " + saved["failure"]["next_retry_at"] + "."; }
        if saved["last_delivery"].get("at", None) { return "Last sent " + saved["last_delivery"]["at"] + " (" + str(saved["last_delivery"]["count"]) + " reminders)."; }
        return "";
    }

    async def ask_notifications() -> None {
        if not window.Notification { return; }
        notify_permission = await window.Notification.requestPermission();
    }

    def background_status(bg: dict) -> str {
        if not bg.get("enabled", None) { return "Off. Sales and reminders are checked when you open the app or press Check for updates."; }
        status = "Checked every " + str(bg["interval_minutes"]) + " minutes while the server is running, even when this page is closed.";
        if bg["last_run_at"] == "" { status += " First check within a minute."; }
        else { status += " Last check " + bg["last_run_at"] + "; next after " + bg["next_check_at"] + "."; }
        if bg["quiet"] { status += " Paused during quiet hours."; }
        if bg["last_error"] != "" { status += " Last error: " + bg["last_error"]; }
        return status;
    }

    # What the active data source can actually tell the user. Kroger branches give
    # current prices and stock only when the server has Kroger credentials.
    def live_prices() -> bool {
        creds = snapshot.get("workspace", {}).get("credentials", {});
        return bool(creds.get("KROGER_CLIENT_ID", None)) and bool(creds.get("KROGER_CLIENT_SECRET", None));
    }

    """Footer: the last server message, or when prices were last checked."""
    def status_line() -> str {
        if notice != "" and not notice.startswith("Data mode") and not notice.startswith("Checked ") { return notice; }
        when = snapshot.get("checked_at", "");
        return ("Updated " + clock(when) if when else "") + ("" if live_prices() else " · Kroger prices unavailable, using price history");
    }

    def source_detail() -> str {
        if live_prices() { return "Kroger branches near your address show current prices and stock levels, rechecked before you accept a visit. Other stores show historical Open Prices records or location only."; }
        return "Nearby stores use your address. Open Prices coverage varies; today's prices and stock are unknown. Add Kroger credentials for current prices.";
    }

    """Brand, flavor and size the shopper asked for, e.g. "Lay's · classic · 8 oz"."""
    def spec_text(item: dict) -> str {
        return [item.get(k, "") for k in ["brand", "variant", "size"] if item.get(k, "")].join(" · ");
    }

    def show_reminders() -> None {
        go("list");
        setTimeout(lambda {
            el = document.getElementById("interests");
            if el { el.scrollIntoView({"block": "start", "behavior": "smooth"}); }
        }, 0);
    }
    can with (snapshot, busy) entry {
        listener = lambda e: any { operate("view", {}, e.detail or ""); };
        window.addEventListener("shopping-chat-updated", listener);
        return lambda { window.removeEventListener("shopping-chat-updated", listener); };
    }

    def intent_rows() -> list {
        intent = snapshot["workspace"]["pending_intent"];
        data = intent.get("feedback", None) or intent;
        rows = [];
        for key in Object.keys(data) {
            if key in ["intent", "confidence"] { continue; }
            text = JSON.stringify(data[key]);
            if text.slice(0, 1) == "\"" { text = text.slice(1, -1); }
            rows.append([key.replace("_", " "), text]);
        }
        return rows;
    }

    """Everything the trip bar shows for the current stage."""
    def bar() -> dict {
        ws = snapshot.get("workspace", None);
        budget = snapshot.get("budget", None);
        left = {"id": "left", "label": "Budget left this week", "value": money(budget["remaining"]) if budget and budget["weekly_budget"] > 0 and budget["remaining"] is not None else "Not set", "unit": "", "tone": "bad" if budget and budget.get("over_budget", None) else ""};
        spent = {"id": "spent", "label": "Spent this week", "value": money(budget["spent"]) if budget else "$0.00", "unit": "", "tone": ""};
        day_names = {"MON": "Monday", "TUE": "Tuesday", "WED": "Wednesday", "THU": "Thursday", "FRI": "Friday", "SAT": "Saturday", "SUN": "Sunday"};
        out = {"title": "Your shopping trip", "sub": "", "pill": "", "tone": "", "stats": [], "prefs": [], "first": False};
        if not ws { out["sub"] = "Loading…"; return out; }
        profile = ws["profile"];
        if len(profile["free_windows"]) > 0 {
            code = profile["free_windows"][0].strip().slice(0, 3).upper();
            if day_names.get(code) { out["title"] = day_names[code] + " shopping"; }
        }
        out["prefs"] = [{"id": "free", "text": ([window_label(w) for w in profile["free_windows"]].join(", ") or "No free time saved")},
            {"id": "travel", "text": ([m.slice(0, 1) + m.slice(1).lower() for m in profile["transport"]].join(" + ") or "No travel modes") + (" · ≤" + str(profile["max_transfers"]) + " transfers" if "BUS" in profile["transport"] else "")},
            {"id": "carry-limit", "text": "Carry limit " + kg(profile["carry_limit_kg"])}];
        out["prefs"].append({"id": "address", "text": ("From " + short_address(profile["address"]) if profile["address"] else "No start address")});
        items = current_items();
        accepted = accepted_plans(snapshot);
        if stage == "shop" and len(accepted) > 0 {
            plan = accepted[0];
            shelf = [item for item in plan["items"] if item["outcome"] == "PENDING" and item.get("fulfillment", None) != "DELIVERY"];
            weights = {};
            for row in carried(plan) { weights[row["name"]] = row["kg"]; }
            in_basket = [item for item in shelf if picked.get(plan["key"] + "|" + item["category"], False)];
            count = len(in_basket);
            bag = tally([weights.get(item["category"], None) for item in in_basket]);
            basket = tally([item_amount(item) for item in in_basket]);
            ends = trip_ends(plan.get("route", None));
            Object.assign(out, {"title": "At " + plan["store"]["name"], "sub": ("Home by " + ends["home"]) if ends["home"] else "Tick items as they go in your basket", "pill": "SHOPPING", "tone": "go",
                "stats": [{"id": "picked", "label": "In your basket", "value": str(count), "unit": "/ " + str(len(shelf)), "tone": ""},
                    {"id": "bags", "label": "In your bags", "value": tally_label(bag, lambda v: float -> str { return str(Math.round(v * 10) / 10); }), "unit": "/ " + kg(profile["carry_limit_kg"]), "tone": "bad" if bag["total"] > profile["carry_limit_kg"] else ("" if bag["missing"] > 0 else "ok")},
                    {"id": "basket", "label": "Basket estimate", "value": tally_label(basket, money), "unit": "", "tone": ""}]});
            return out;
        }
        if stage == "shop" and recorded.get("store", None) {
            Object.assign(out, {"sub": "Done · " + str(recorded["bought"]) + " bought at " + recorded["store"], "pill": "COMPLETE", "tone": "go",
                "stats": [{"id": "paid", "label": "Paid this trip", "value": money(recorded["paid"]), "unit": "", "tone": ""}, spent, left]});
            return out;
        }
        opens = open_plans(snapshot);
        if stage in ["options", "route"] and len(opens) > 0 {
            plan = route_plan() if stage == "route" else (recommended([facts(p) for p in opens]) or {}).get("plan", None);
            fits = len([row for row in [facts(p) for p in opens] if row["eligible"]]);
            if plan {
                row = facts(plan);
                ends = trip_ends(plan.get("route", None));
                over = row["weight"] is not None and row["weight"] > profile["carry_limit_kg"];
                carry_value = "Unknown" if row["weight"] is None else ("≥ " if row["weight_missing"] > 0 else "") + str(Math.round(row["weight"] * 10) / 10);
                review = plan["status"] == "NEEDS_REVIEW";
                Object.assign(out, {"sub": (("Leave " + ends["leave"] + (" · home " + ends["home"] if ends["home"] else "")) if stage == "route" and ends["leave"] else (str(fits) + " of " + str(len(opens)) + " options fit your limits")),
                    "pill": ("NEEDS REVIEW" if review else ("READY TO ACCEPT" if stage == "route" else str(fits) + (" OPTION FITS" if fits == 1 else " OPTIONS FIT"))), "tone": "amber" if review else "",
                    "stats": [({"id": "total", "label": "Estimated total", "value": money(row["total"]), "unit": "", "tone": ""} if row["total"] is not None or row["items"] is None else {"id": "total", "label": "Items · fare unknown", "value": money(row["items"]), "unit": "", "tone": ""}),
                        {"id": "carry", "label": "You carry", "value": carry_value, "unit": "" if row["weight"] is None else "/ " + kg(profile["carry_limit_kg"]), "tone": "bad" if over else ("" if row["weight"] is None or row["weight_missing"] > 0 else "ok")}, left]});
            } else {
                Object.assign(out, {"sub": "No option fits your limits yet", "pill": "NO OPTION FITS", "tone": "amber", "stats": [{"id": "plans", "label": "Options checked", "value": str(len(opens)), "unit": "", "tone": ""}, spent, left]});
            }
            return out;
        }
        out["first"] = len(items) == 0 and not profile["address"] and len(all_plans()) == 0;
        Object.assign(out, {"sub": (str(len(items)) + (" item" if len(items) == 1 else " items") + " on your list · not planned yet") if len(items) > 0 else "Your list is empty",
            "pill": "BUILDING LIST" if len(items) > 0 else "NEW TRIP",
            "stats": [spent, left]});
        return out;
    }

    """How many steps are really finished, in order: a list, a chosen plan, an accepted plan, a recorded trip."""
    def progress() -> int {
        accepted_now = len(accepted_plans(snapshot)) > 0;
        trip_done = bool(recorded.get("store", None));
        steps = [len(current_items()) > 0 or len(all_plans()) > 0, bool(find_plan(selected)) or accepted_now or trip_done, accepted_now or trip_done, trip_done];
        count = 0;
        for finished_step in steps {
            if not finished_step { break; }
            count += 1;
        }
        return count;
    }

    trip = bar();
    ws = snapshot.get("workspace", None);
    items = current_items();
    accepted = accepted_plans(snapshot);

    return <section className="shopping-panel" aria-label="Shopping workspace">
        {if toast.get("key", None) {
            <div className="toast" role="status"><span><small>New reminder</small>{toast["message"]}</span><span></span>
                <div className="toast-actions"><button type="button" onClick={lambda e: MouseEvent { toast = {}; show_reminders(); }}>View</button><button type="button" className="ghost" onClick={lambda e: MouseEvent { toast = {}; }}>Dismiss</button></div></div>
        }}
        <TripBar title={trip["title"]} sub={trip["sub"]} pill={trip["pill"]} tone={trip["tone"]} stats={trip["stats"]} prefs={trip["prefs"]} edit={lambda { view = "profile"; }} first_use={trip["first"]} />
        {if view == "" {
            <StageNav stage={stage or "list"} progress={progress()} go={go} />
        } else {
            <div className="view-head"><h2>{"Budget" if view == "budget" else "Preferences"}</h2><button type="button" onClick={lambda e: MouseEvent { view = ""; }}>← Back to trip</button></div>
        }}
        <div className="workspace-content" role="tabpanel" id="stage-panel" aria-labelledby={("stage-" + (stage or "list")) if view == "" else ""} tabIndex={0} key={view or stage}>
            {if error_notice != "" { <div className="error-banner" role="alert"><span>{error_notice}</span><button type="button" aria-label="Dismiss error" onClick={lambda e: MouseEvent { error_notice = ""; }}>×</button></div> }}
            {if ws and ws["pending_id"] != "" {
                <div className="pending-request">
                    <h3>Confirm the assistant's change</h3>
                    <p>Review what the assistant wants to save. Nothing changes until you confirm.</p>
                    <dl>{[[<dt key={"k" + row[0]}>{row[0]}</dt>, <dd key={"v" + row[0]}>{row[1]}</dd>] for row in intent_rows()]}</dl>
                    <button className="go" disabled={busy} onClick={lambda e: MouseEvent { operate("confirm_chat", {"id": ws["pending_id"]}); }}>Confirm changes</button>
                    <button className="ghost" disabled={busy} onClick={lambda e: MouseEvent { operate("discard_chat", {}); }}>Discard</button>
                </div>
            }}
            {if view == "budget" and snapshot.get("budget", None) { <BudgetPanel budget={snapshot["budget"]} busy={busy} operate={operate} /> }}
            {if view == "profile" and ws {
                <div>
                    <WorkspacePanel key={JSON.stringify(ws["profile"])} workspace={ws} busy={busy} operate={operate} category={category} view="profile" select={select} />
                    <section aria-label="Reminder settings">
                        <h3>Reminders</h3>
                        <div className="background-reminders">
                            <label><input type="checkbox" checked={snapshot.get("background", {}).get("enabled", False)} disabled={busy} onChange={lambda e: ChangeEvent { operate("background", {"enabled": e.target.checked}); }} /> Check for sales and restock reminders in the background</label>
                            <p>{background_status(snapshot.get("background", {}))}</p>
                            {if notify_permission == "default" { <button type="button" onClick={lambda e: MouseEvent { ask_notifications(); }}>Enable desktop notifications</button> }}
                            {if notify_permission == "denied" { <p>Desktop notifications are blocked in this browser; reminders still appear here.</p> }}
                            {if notify_permission == "granted" { <p>Desktop notifications are on while this page is open.</p> }}
                        </div>
                        {if snapshot.get("delivery", None) {
                        <div className="background-reminders delivery-settings">
                            <h4>Email reminders</h4>
                            <p>Background checks email new reminders even when no CartCompass page is open, at most once per reminder and never during quiet hours.</p>
                            <label>Email address<input aria-label="Reminder email" type="email" value={email} maxLength="254" onChange={lambda e: ChangeEvent { email = e.target.value; }} /></label>
                            <label className="check-row"><input type="checkbox" checked={email_on} disabled={not snapshot["delivery"]["email_available"]} onChange={lambda e: ChangeEvent { email_on = e.target.checked; }} /> Email me new reminders</label>
                            {if not snapshot["delivery"]["email_available"] { <p>Email needs SMTP settings in the server's .env (see docs/NOTIFICATIONS.md).</p> }}
                            <p>{delivery_status(snapshot["delivery"])}</p>
                            <div className="row-actions">
                                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("notify_settings", {"email": email, "email_enabled": email_on}); }}>Save email settings</button>
                                <button type="button" disabled={busy or snapshot["delivery"]["email"] == "" or not snapshot["delivery"]["email_available"]} onClick={lambda e: MouseEvent { operate("notify_test", {}); }}>Send test email</button>
                            </div>
                        </div>
                        }}
                    </section>
                </div>
            }}
            {if view == "" and (stage or "list") == "list" {
            <div>
                <div className="list-intro"><div><h3 id="chg-list">Your shopping list</h3><p>Add items here or tell the assistant what you need.</p></div></div>
                {if len(items) == 0 { <div className="empty-list"><span className="empty-symbol" aria-hidden="true">＋</span><h3>Room for your next essentials.</h3><p>Your list is empty. Tell the assistant what you need, or add your first item below.</p></div> }}
                {[<div key={item["category"]} className="interest-row"><div><span className="item-name">{str(item.get("qty", 1)) + " × " + item["category"]}</span>{if spec_text(item) != "" or item["status"] == "PAUSED" { <span className="item-meta">{"Not this trip" if item["status"] == "PAUSED" else spec_text(item)}</span> }}</div><div className="row-actions">
                    <button type="button" disabled={busy} title={"Put it back on this trip" if item["status"] == "PAUSED" else "Keep it saved but leave it out of this trip"} onClick={lambda e: MouseEvent { operate("interest_status", {"category": item["category"], "status": "ACTIVE" if item["status"] == "PAUSED" else "PAUSED"}); }}>{"Add back" if item["status"] == "PAUSED" else "Not this trip"}</button>
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("feedback", {"id": crypto.randomUUID(), "type": "feedback", "target": item["category"], "reason": "PURCHASED"}); }}>Already have it</button>
                </div></div> for item in items]}
                <details className="quick-add" open={len(items) == 0}><summary>+ Add an item</summary>
                    <form onSubmit={save}>
                        <label>Item <input aria-label="Item" list="categories" placeholder="e.g. milk" required value={category} onChange={lambda e: ChangeEvent { category = e.target.value; }} /><datalist id="categories">{[<option key={name} value={name} /> for name in ["milk", "eggs", "rice", "laundry detergent", "paper towels", "yogurt", "dish soap", "tofu", "soy sauce", "coffee"]]}</datalist></label>
                        <label>Packages <input aria-label="Packages" type="number" min="1" max="20" required value={quantity} onChange={lambda e: ChangeEvent { quantity = e.target.value; }} /></label>
                        <button type="submit" className="go" disabled={busy}>Add to list</button>
                    </form>
                </details>
                <InterestStrip snapshot={snapshot} busy={busy} operate={operate} />
                {if len([item for item in snapshot["interests"] if not item.get("in_current_list", True)]) > 0 {
                    <details>
                        <summary>From earlier trips</summary>
                        <p>Items from earlier trips. They are not planned unless you add them back.</p>
                        {[<div key={item["category"]} className="interest-row">
                            <span>{str(item["qty"]) + " × " + item["category"] + (" · " + spec_text(item) if spec_text(item) != "" else "")}</span>
                            <button disabled={busy} onClick={lambda e: MouseEvent { operate("interest_status", {"category":item["category"], "status":"ACTIVE"}); }}>Add to this trip</button>
                        </div> for item in snapshot["interests"] if not item.get("in_current_list", True)]}
                    </details>
                }}
                <div className="cta-row">
                    <span>{("We'll use your current location as the starting point. You can change it in Preferences." if ws and not ws["profile"]["address"] else "Compare stores, routes and delivery for this list.") if len(items) > 0 else "Add at least one item to compare options."}</span>
                    <button className="primary cta" disabled={busy or len(items) == 0} onClick={lambda e: MouseEvent { find_options(); }}>Find shopping options →</button>
                </div>
            </div>
            }}
            {if view == "" and stage == "options" and ws {
                <WorkspacePanel key={JSON.stringify(ws["profile"])} workspace={ws} busy={busy} operate={operate} category={category} view="plans" select={select} auto_locate={locate_now} on_address={after_address} />
            }}
            {if view == "" and stage == "route" and ws {
                <RouteStage plan={route_plan()} workspace={ws} busy={busy} operate={operate} find={find_options} />
            }}
            {if view == "" and stage == "shop" {
                <div>
                    {if len(accepted) > 0 {
                        <div>
                            {if recorded.get("plan", None) == accepted[0]["key"] { <TripComplete summary={recorded} budget={snapshot.get("budget", None)} plan={accepted[0]} busy={busy} operate={operate} open_budget={lambda { view = "budget"; }} /> }}
                            <InStore plan={accepted[0]} picked={picked} toggle={toggle_pick} busy={busy} operate={operate} finished={finished} />
                        </div>
                    } elif recorded.get("store", None) {
                        <TripComplete summary={recorded} budget={snapshot.get("budget", None)} plan={find_plan(recorded["plan"])} busy={busy} operate={operate} open_budget={lambda { view = "budget"; }} />
                    } else {
                        <div className="empty-list"><h3>Nothing to shop for yet</h3><p>Accept a plan on the Route step and your in-store list appears here.</p><button className="primary" onClick={lambda e: MouseEvent { go("options"); }}>See options</button></div>
                    }}
                </div>
            }}
        </div>
        <div className="sync-status"><p role="status" aria-live="polite" title={source_detail()}>{status_line()}</p><button type="button" disabled={busy} title="Check prices, sales and reminders again" onClick={lambda e: MouseEvent { operate("refresh", {}); }}>{"Checking…" if busy else "Check for updates"}</button></div>
    </section>;
}
