"""Responsive shopping workspace with a persistent conversational assistant."""
sv import from ..server.chat { SendMessage, ChatHistory, StartShoppingPlan }
import from .shopping { ShoppingPanel }
import from .theme { AppStyles }

def:pub ChatApp -> JsxElement {
    has messages: list[dict] = [], draft: str = "", pending: bool = True,
        history_notice: str = "", workspace_epoch: int = 0;
    async def send(e: FormEvent) -> None;
    async def history(clear: bool = False) -> None;
    async def new_plan() -> None;
    can with [] entry { history(); }
    can with (messages, pending) entry {
        el: any = document.querySelector(".chat-log");
        if el { el.scrollTop = el.scrollHeight; }
    }
    return <div className="app-shell">
        <AppStyles />
        <header className="app-header">
            <a className="brand" href="#" aria-label="CartCompass home"><span className="brand-icon" aria-hidden="true">↗</span><span>CartCompass<small>YOUR EVERYDAY SHOPPING ASSISTANT</small></span></a>
            <div className="new-trip"><button className="primary" disabled={pending} onClick={lambda e: MouseEvent { new_plan(); }}>+ New shopping plan</button>
                <span>Fresh list. Saved preferences.</span>
            </div>
        </header>
        <div className="page-intro"><div><p className="eyebrow">A LITTLE PLANNING. A BETTER SHOP.</p><h1>Your next shop starts here.</h1><p>Build your list, find a store, and make a plan that fits your day.</p></div>
            <details className="reset-help"><summary>Starting a new trip?</summary><p>New shopping plan starts a fresh list and conversation, pauses previous needs and cancels unfinished plans. Your address, preferences and purchase history stay saved.</p></details>
        </div>
        <main className="app-columns">
            <ShoppingPanel key={workspace_epoch} />
            <aside className="assistant-panel" aria-label="Shopping assistant">
                <div className="assistant-heading"><span className="assistant-icon" aria-hidden="true">✦</span><div><h2>Let’s plan together</h2><p>Tell me what you need. I’ll ask the rest.</p></div></div>
                <div className="chat-tools"><span>Conversation saved automatically</span><button className="text-button" disabled={pending} onClick={lambda e: MouseEvent { history(True); }} title="Clears messages only. Your list and plans stay saved.">Clear chat history</button></div>
                {if history_notice { <p className="inline-alert" role="alert">{history_notice}</p> }}
                <div className="chat-log" role="log" aria-label="Conversation" aria-live="polite">
                    {if len(messages) == 0 {
                        <div className="chat-empty"><div className="empty-symbol" aria-hidden="true">↗</div><h3>A plan begins with a need.</h3><p>Start with your shopping list. I can ask for your address, travel preferences and free time as we go.</p><button disabled={pending} onClick={lambda e: MouseEvent { draft = "Plan a shopping trip for milk and rice. Ask me for any missing details."; }}>Help me plan for milk and rice ↗</button><small>Your answers update the shopping workspace automatically.</small></div>
                    }}
                    {[<div key={str(idx)} className={"message message-user" if turn["role"] == "user" else "message message-assistant"}><span className="message-role">{"You" if turn["role"] == "user" else "CartCompass"}</span><div>{turn["content"]}</div></div> for (idx, turn) in enumerate(messages)]}
                    {if pending { <p className="thinking" role="status">Working on your shopping workspace…</p> }}
                </div>
                <div className="composer-wrap"><form onSubmit={send} className="chat-composer"><input aria-label="Message your shopping assistant" type="text" value={draft} onChange={lambda e: ChangeEvent { draft = e.target.value; }} placeholder="Tell me what you need…" /><button className="primary" type="submit" disabled={pending or not draft.strip()}>{"Sending…" if pending else "Send ↗"}</button></form><p>Just reply here — your list and preferences stay in sync.</p></div>
            </aside>
        </main>
        <footer className="app-footer"><span>Thoughtful trips. Clearer choices.</span><span>Historical prices are references, not current offers.</span></footer>
    </div>;
}
