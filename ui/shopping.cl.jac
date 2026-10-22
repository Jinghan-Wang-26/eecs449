"""Small structured shopping panel alongside the existing chat."""

sv import from ..server.shopping { ShoppingAction }
import from .workspace { WorkspacePanel }

def:pub ShoppingPanel -> JsxElement {
    has snapshot: dict = {"interests": [], "discoveries": [], "reminders": [], "quiet": False},
        category: str = "milk",
        kind: str = "NEED",
        quantity: str = "1",
        target: str = "4.50",
        days: str = "7",
        purchased: str = "",
        busy: bool = False,
        notice: str = "Open the panel and refresh to load your saved interests.";

    async def operate(action: str, data: dict) -> None;
    async def save(e: FormEvent) -> None;

    can with [] entry { operate("view", {}); }
    can with [] entry {
        listener = lambda e: any { operate("view", {}); };
        window.addEventListener("shopping-chat-updated", listener);
        return lambda { window.removeEventListener("shopping-chat-updated", listener); };
    }

    return <details open style={{"fontFamily": "system-ui, sans-serif", "background": "#fffdf8", "border": "1px solid #d6d3d1", "borderRadius": "12px", "padding": "12px", "marginBottom": "12px"}}>
        <summary style={{"cursor": "pointer", "fontWeight": "600"}}>Shopping workspace</summary>
        <div style={{"maxHeight": "55vh", "overflowY": "auto", "paddingTop": "10px"}}>
            <style>{".workspace-panel label { display: grid; gap: 4px; margin: 8px 0; } .profile-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; } .result-card, .pending-request { border: 1px solid #ddd; padding: 12px; border-radius: 8px; margin: 10px 0; } .workspace-panel button { margin: 4px; padding: 6px 10px; } .workspace-panel input, .workspace-panel select { padding: 6px; max-width: 100%; } .pending-request pre { white-space: pre-wrap; overflow-wrap: anywhere; }"}</style>
            {if snapshot.get("workspace") { <WorkspacePanel key={JSON.stringify(snapshot["workspace"]["profile"])} workspace={snapshot["workspace"]} mode={snapshot["data_mode"]} busy={busy} operate={operate} category={category} /> }}
            <p>{"Demo catalog · simulated prices and stock." if snapshot.get("data_mode", "mock") == "mock" else "Live catalog · missing fields remain unknown."} Checks run when you refresh.</p>
            <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("refresh", {}); }}>Refresh shopping tools</button>
            <p role="status" aria-live="polite">{notice}</p>
            <form onSubmit={save} style={{"display": "flex", "flexWrap": "wrap", "gap": "8px", "alignItems": "end"}}>
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
            <h3>Saved interests</h3>
            {[<div key={item["category"]} style={{"marginBottom": "8px"}}>
                <span>{item["category"] + " · " + item["kind"] + " · " + item["status"] + " "}</span>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("interest_status", {"category": item["category"], "status": "ACTIVE" if item["status"] == "PAUSED" else "PAUSED"}); }}>{"Resume" if item["status"] == "PAUSED" else "Pause"}</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("feedback", {"id": crypto.randomUUID(), "type": "feedback", "target": item["category"], "reason": "PURCHASED"}); }}>Purchased</button>
            </div> for item in snapshot["interests"]]}
            <h3>Discoveries</h3>
            {if len(snapshot["discoveries"]) == 0 { <p>No new recommendations. Save an interest to get started.</p> }}
            {[<div key={item["key"]} style={{"marginBottom": "10px"}}>
                <strong>{item["name"]}</strong><p>{item["reason"]}</p>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("discovery", {"key": item["key"], "action": "accept"}); }}>Add to shopping needs</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("discovery", {"key": item["key"], "action": "dismiss"}); }}>Not interested</button>
            </div> for item in snapshot["discoveries"]]}
            <h3>Reminders</h3>
            {if snapshot["quiet"] { <p>Quiet hours are active. Refresh after quiet hours to see reminders.</p> }}
            {if not snapshot["quiet"] and len(snapshot["reminders"]) == 0 { <p>No reminders are due from fresh catalog data.</p> }}
            {[<div key={item["key"]} style={{"marginBottom": "10px"}}>
                <p>{item["message"]}</p>
                {if item["kind"] != "PLAN_CHANGE" { <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "add"}); }}>Add to shopping needs</button> }}
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "snooze"}); }}>Snooze</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "ignore"}); }}>Show less often</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("reminder", {"key": item["key"], "action": "dismiss"}); }}>Dismiss</button>
            </div> for item in snapshot["reminders"]]}
        </div>
    </details>;
}
