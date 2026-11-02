"""Responsive shopping workspace with a persistent conversational assistant.

New users start with the conversation alone. The workspace appears once there is
something to show (a list item or a plan), or when the user asks for it."""
sv import from ..server.chat { SendMessage, ChatHistory, StartShoppingPlan }
import from .shopping { ShoppingPanel }
import from .theme { AppStyles }

def:pub ChatApp -> JsxElement {
    has messages: list[dict] = [], draft: str = "", pending: bool = True,
        history_notice: str = "", workspace_epoch: int = 0,
        changes: list = [], pane: str = "plan", unread: int = 0, plan_updated: bool = False,
        summary: dict = {}, manual: bool = False, boot_done: bool = False;
    async def send(e: FormEvent) -> None;
    async def history(clear: bool = False) -> None;
    async def new_plan() -> None;
    can with [] entry {
        history();
        # Never keep the workspace hidden if it cannot report its state.
        timer = setTimeout(lambda { boot_done = True; }, 2500);
        return lambda { clearTimeout(timer); };
    }
    can with (messages, pending, changes) entry {
        el: any = document.querySelector(".chat-log");
        if el { el.scrollTop = el.scrollHeight; }
    }

    # The workspace reports whether it has anything to show and what the next steps are.
    can with (summary) entry {
        listener = lambda e: any {
            # When the first item appears, keep phone users in the conversation and flag the plan.
            if summary.get("ready", False) and summary.get("empty", False) and not e.detail["empty"] {
                pane = "assistant"; plan_updated = True;
            }
            summary = e.detail;
        };
        window.addEventListener("workspace-summary", listener);
        return lambda { window.removeEventListener("workspace-summary", listener); };
    }
    # Declared after the listener so the first reply is not missed.
    can with [] entry { window.dispatchEvent(new(CustomEvent, "workspace-summary-request")); }

    """A glowing dot travels from the newest change card to what changed, then the
    target flashes. Skipped when the user prefers reduced motion or the target is hidden."""
    def fly(target: str) -> None {
        el = document.getElementById(target);
        cards = document.querySelectorAll(".change-card");
        if not el { return; }
        el.classList.remove("hl");
        x = el.offsetWidth;
        reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        card = cards[len(cards) - 1] if len(cards) > 0 else None;
        a = card.getBoundingClientRect() if card else None;
        b = el.getBoundingClientRect();
        if reduce or not a or a.width == 0 or b.width == 0 {
            el.classList.add("hl");
            return;
        }
        dot = document.createElement("i");
        dot.className = "beam";
        dot.setAttribute("aria-hidden", "true");
        document.body.appendChild(dot);
        x1 = a.left + 14; y1 = a.top + 14;
        x2 = b.left + b.width / 2 - 6; y2 = b.top + b.height / 2 - 6;
        mx = (x1 + x2) / 2; my = Math.min(y1, y2) - 80;
        motion = dot.animate([
            {"transform": "translate(" + str(x1) + "px," + str(y1) + "px) scale(.5)", "opacity": 0},
            {"transform": "translate(" + str(x1) + "px," + str(y1) + "px) scale(1)", "opacity": 1, "offset": 0.12},
            {"transform": "translate(" + str(mx) + "px," + str(my) + "px)", "opacity": 1, "offset": 0.55},
            {"transform": "translate(" + str(x2) + "px," + str(y2) + "px) scale(.6)", "opacity": 0}
        ], {"duration": 900, "delay": 150, "easing": "cubic-bezier(.5,0,.3,1)", "fill": "both"});
        motion.onfinish = lambda e: any { dot.remove(); el.classList.add("hl"); };
    }

    # The workspace reports what a chat reply changed; show it under that reply.
    can with (messages, changes, pane) entry {
        listener = lambda e: any {
            changes = changes.concat([{"id": crypto.randomUUID(), "at": len(messages), "rows": e.detail}]);
            if pane == "assistant" { plan_updated = True; }
            setTimeout(lambda {
                for row in e.detail.slice(1) { flash(row["target"]); }
                fly(e.detail[0]["target"]);
            }, 80);
        };
        window.addEventListener("workspace-changed", listener);
        return lambda { window.removeEventListener("workspace-changed", listener); };
    }

    def flash(target: str) -> None {
        el = document.getElementById(target);
        if not el { return; }
        el.classList.remove("hl");
        x = el.offsetWidth;
        el.classList.add("hl");
    }

    def open_view(name: str) -> None {
        manual = True; pane = "plan";
        window.dispatchEvent(new(CustomEvent, "cartcompass-view", {"detail": name}));
    }

    """Run a next-step button in the workspace and show the workspace on phones."""
    def act(code: str) -> None {
        manual = True; pane = "plan"; plan_updated = False;
        window.dispatchEvent(new(CustomEvent, "cartcompass-action", {"detail": code}));
    }

    def start_myself() -> None {
        manual = True; pane = "plan";
    }

    def entries() -> list {
        out = [{"type": "change", "key": card["id"], "rows": card["rows"]} for card in changes if card["at"] == 0];
        for (idx, turn) in enumerate(messages) {
            out.append({"type": "message", "key": "m" + str(idx), "turn": turn, "last": idx == len(messages) - 1});
            for card in changes {
                if card["at"] == idx + 1 { out.append({"type": "change", "key": card["id"], "rows": card["rows"]}); }
            }
        }
        return out;
    }

    def render(part: dict) -> any {
        if part["type"] == "change" {
            return <div key={part["key"]} className="change-card" role="status"><h4>Plan updated</h4>{[<div key={row["label"]}><span>{row["label"]}</span><span>{(row["before"] + " → " + row["after"]) if row["before"] else row["after"]}</span></div> for row in part["rows"]]}</div>;
        }
        turn = part["turn"];
        return <div key={part["key"]} className={"message message-user" if turn["role"] == "user" else "message message-assistant"}><span className="message-role">{"You" if turn["role"] == "user" else "CartCompass"}</span><div>{turn["content"]}</div></div>;
    }

    ready = summary.get("ready", False) or boot_done;
    onboarding = summary.get("ready", False) and summary.get("empty", False) and not manual;
    welcome = onboarding and len(messages) == 0 and not pending;
    # While the assistant is waiting for an answer, the answer is the next step.
    last = messages[len(messages) - 1] if len(messages) > 0 else None;
    asking = bool(last) and last["role"] == "assistant" and "?" in last["content"].strip().split("\n").pop();
    next_steps = summary.get("actions", []) if not onboarding and not asking else [];
    examples = ["I need milk, eggs and rice this weekend. I don't have a car.", "Plan a Saturday grocery run under $60.", "What's the cheapest way to get laundry detergent home?"];

    return <div className="app-shell">
        <AppStyles />
        <header className="topbar">
            <a className="brand" href="#" aria-label="CartCompass home"><span className="brand-icon" aria-hidden="true">↗</span>CartCompass</a>
            <button type="button" onClick={lambda e: MouseEvent { open_view("budget"); }}>Budget</button>
            <button type="button" onClick={lambda e: MouseEvent { open_view("profile"); }}>Preferences</button>
            <button type="button" className="new-trip" disabled={pending} title="Starts a fresh list and conversation. Your address, preferences and purchase history stay saved." onClick={lambda e: MouseEvent { manual = False; new_plan(); }}>+ New trip</button>
            {if not onboarding {
                <div className="pane-switch" role="group" aria-label="Show">
                    <button type="button" aria-pressed={pane == "plan"} onClick={lambda e: MouseEvent { pane = "plan"; plan_updated = False; }}>Plan{if plan_updated { <em>new</em> }}</button>
                    <button type="button" aria-pressed={pane == "assistant"} onClick={lambda e: MouseEvent { pane = "assistant"; unread = 0; }}>Assistant{if unread > 0 { <em>{str(unread)}</em> }}</button>
                </div>
            }}
        </header>
        <main className={"app-columns pane-" + pane + (" onboarding" if onboarding else "") + ("" if ready else " booting")}>
            <ShoppingPanel key={workspace_epoch} />
            <aside className="assistant-panel" aria-label="Shopping assistant">
                {if not welcome {
                    <div className="assistant-heading"><span className={"orb busy" if pending else "orb"} aria-hidden="true"></span><div><h2>Assistant</h2><p>{"Tell me what you need. I'll build the list and plan the trip." if onboarding else "What you say here updates your plan."}</p></div>
                        <button className="text-button" disabled={pending} onClick={lambda e: MouseEvent { changes = []; history(True); }} title="Clears messages only. Your list and plans stay saved.">Clear chat</button></div>
                }}
                {if history_notice { <p className="inline-alert" role="alert">{history_notice}</p> }}
                {if welcome {
                    <section className="welcome" aria-label="Start a shopping trip">
                        <span className="orb welcome-orb" aria-hidden="true"></span>
                        <h1>What do you need to buy?</h1>
                        <p>Say it in your own words. I'll ask where you're starting from and when you're free, then compare stores, buses and delivery for you.</p>
                        <form onSubmit={send} className="welcome-composer"><input aria-label="Tell CartCompass what you need" type="text" value={draft} autoFocus={True} onChange={lambda e: ChangeEvent { draft = e.target.value; }} placeholder="Milk, eggs, rice…" /><button className="go" type="submit" disabled={pending or not draft.strip()}>Start ↗</button></form>
                        <div className="examples">{[<button key={ex} type="button" onClick={lambda e: MouseEvent { draft = ex; }}>{ex}</button> for ex in examples]}</div>
                        <div className="welcome-links">
                            <button type="button" className="text-button" onClick={lambda e: MouseEvent { start_myself(); }}>I'd rather add items myself</button>
                        </div>
                    </section>
                } else {
                    <div className="chat-log" role="log" aria-label="Conversation" aria-live="polite">
                        {if len(messages) == 0 and not pending {
                            <div className="chat-empty"><span className="orb" aria-hidden="true" style={{"display": "inline-block", "width": "44px", "height": "44px"}}></span><h3>Ask me anything about this trip.</h3><p>For example: "Can I leave after 3?" or "Deliver the heavy items."</p></div>
                        }}
                        {[render(part) for part in entries()]}
                        {if len(next_steps) > 0 and not pending {
                            <div className="next-steps" aria-label="Suggested next steps"><span>Next step</span>{[<button key={step["id"]} type="button" className={"go" if i == 0 else ""} onClick={lambda e: MouseEvent { act(step["id"]); }}>{step["label"]}</button> for (i, step) in enumerate(next_steps)]}</div>
                        }}
                        {if pending { <p className="thinking" role="status"><span className="orb busy" aria-hidden="true"></span>{"Working on your shopping list…" if onboarding else "Working on your shopping workspace…"}</p> }}
                    </div>
                }}
                {if not welcome {
                    <div className="composer-wrap">
                        <form onSubmit={send} className="chat-composer"><input aria-label="Message your shopping assistant" type="text" value={draft} onChange={lambda e: ChangeEvent { draft = e.target.value; }} placeholder={"Tell me what you need…" if onboarding else "Tell me what to change…"} /><button className="primary" type="submit" disabled={pending or not draft.strip()}>{"Sending…" if pending else "Send ↗"}</button></form>
                        {if onboarding {
                            <p>{"Your list appears as soon as you mention an item · "}<button type="button" className="text-button" onClick={lambda e: MouseEvent { start_myself(); }}>Open the workspace</button></p>
                        } else {
                            <p>Your list and preferences stay in sync with this chat.</p>
                        }}
                    </div>
                }}
            </aside>
        </main>
        <footer className="app-footer"><span>Thoughtful trips. Clearer choices.</span><span>Prices are snapshots or historical references, not guaranteed offers. Stock is never reserved.</span></footer>
    </div>;
}
