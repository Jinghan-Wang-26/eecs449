"""Profile, start address and store-visit plan controls."""

import from .visits { VisitSearch, VisitHistory }
import from .delivery { DeliveryQuotes }
import from .options { PlanOptions }
import from .planview { parse_windows }
import from .address { AddressPicker }

def:pub WorkspacePanel(workspace: dict, busy: bool, operate: any, category: str, view: str = "plans", select: any = None, auto_locate: bool = False, on_address: any = None) -> JsxElement {
    has max_walk: str = str(workspace["profile"]["max_walk_min"]),
        max_transfers: str = str(workspace["profile"].get("max_transfers", 1)),
        budget: str = str(workspace["profile"]["budget"]),
        carry: str = str(workspace["profile"]["carry_limit_kg"]),
        transport: str = workspace["profile"]["transport"].join(","),
        slots: list = parse_windows(workspace["profile"]["free_windows"]),
        tax: str = "" if workspace["profile"]["tax_rate"] < 0 else str(workspace["profile"]["tax_rate"]),
        travel: str = "" if workspace["profile"]["transport_cost"] < 0 else str(workspace["profile"]["transport_cost"]),
        dietary: str = workspace["profile"]["dietary"].join(","),
        # No longer editable; sent back unchanged so saving keeps any stored value.
        memberships: str = workspace["profile"]["memberships"].join(",");

    can with (workspace["historical_prices"].get("store_key", None), workspace["historical_prices"].get("page", None)) entry {
        el = document.getElementById("historical-price-results");
        if el { el.scrollIntoView({"block": "start", "behavior": "smooth"}); }
    }

    async def save_profile(e: FormEvent) -> None {
        e.preventDefault();
        values = {"weekly_budget": budget, "carry_limit_kg": carry, "max_walk_min": max_walk,
            "max_transfers": max_transfers,
            "transport": [v.strip().upper() for v in transport.split(",") if v.strip()],
            "free_windows": [(slot["raw"] if slot["raw"] else slot["day"] + " " + slot["start"] + "-" + slot["end"]) for slot in slots if slot["raw"] or (slot["day"] and slot["start"] and slot["end"])],
            "dietary": [v.strip() for v in dietary.split(",") if v.strip()],
            "memberships": [v.strip() for v in memberships.split(",") if v.strip()]};
        if tax != "" { values["tax_rate"] = tax; }
        if travel != "" { values["transport_cost"] = travel; }
        await operate("update_profile", values);
    }

    def toggle_mode(value: str) -> None {
        parts = [v.strip().upper() for v in transport.split(",") if v.strip()];
        if value in parts { parts = [v for v in parts if v != value]; }
        else { parts.append(value); }
        transport = parts.join(",");
    }

    def set_slot(idx: int, field: str, value: str) -> None {
        updated = JSON.parse(JSON.stringify(slots));
        updated[idx][field] = value;
        slots = updated;
    }

    modes = [part.strip().upper() for part in transport.split(",") if part.strip()];

    return <section className="workspace-panel">
        {if view == "profile" {
        <div>
            <AddressPicker workspace={workspace} busy={busy} operate={operate} />
            <section><h3>Your shopping profile</h3><p>Tell the assistant your preferences, or adjust them here. Saved preferences carry over to your next trip.</p>
            <form onSubmit={save_profile} className="profile-grid">
                <label>Budget ($)<input aria-label="Budget" type="number" min="0" value={budget} onChange={lambda e: ChangeEvent { budget = e.target.value; }} /></label>
                <label>Carrying limit (kg)<input aria-label="Carrying limit" type="number" min="0.1" step="0.1" value={carry} onChange={lambda e: ChangeEvent { carry = e.target.value; }} /></label>
                <label>Maximum walking segment (minutes)<input aria-label="Maximum walking minutes" type="number" min="0" max="240" value={max_walk} onChange={lambda e: ChangeEvent { max_walk = e.target.value; }} /></label>
                <label>Max bus transfers each way<input aria-label="Maximum bus transfers" type="number" min="0" max="10" step="1" value={max_transfers} onChange={lambda e: ChangeEvent { max_transfers = e.target.value; }} /></label>
                <div className="wide"><label>How you travel</label><div className="chip-group" role="group" aria-label="Transport">{[<button key={m["id"]} type="button" aria-pressed={m["id"] in modes} onClick={lambda e: MouseEvent { toggle_mode(m["id"]); }}>{m["label"]}</button> for m in [{"id": "WALK", "label": "Walk"}, {"id": "BUS", "label": "Bus"}, {"id": "BIKE", "label": "Bike"}, {"id": "CAR", "label": "Car"}]]}</div></div>
                <div className="wide"><label>When you're free</label>
                    {[<div key={str(idx)} className="slot-row">
                        {if slot["raw"] {
                            <input aria-label={"Free time " + str(idx + 1)} value={slot["raw"]} onChange={lambda e: ChangeEvent { set_slot(idx, "raw", e.target.value); }} />
                        } else {
                            <select aria-label={"Day " + str(idx + 1)} value={slot["day"]} onChange={lambda e: ChangeEvent { set_slot(idx, "day", e.target.value); }}><option value="">Day</option>{[<option key={d} value={d}>{d.slice(0, 1) + d.slice(1).lower()}</option> for d in ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]]}</select>
                            <input type="time" aria-label={"Start time " + str(idx + 1)} value={slot["start"]} onChange={lambda e: ChangeEvent { set_slot(idx, "start", e.target.value); }} />
                            <input type="time" aria-label={"End time " + str(idx + 1)} value={slot["end"]} onChange={lambda e: ChangeEvent { set_slot(idx, "end", e.target.value); }} />
                        }}
                        <button type="button" className="ghost" aria-label={"Remove free time " + str(idx + 1)} onClick={lambda e: MouseEvent { slots = [s for (j, s) in enumerate(slots) if j != idx]; }}>Remove</button>
                    </div> for (idx, slot) in enumerate(slots)]}
                    <button type="button" onClick={lambda e: MouseEvent { slots = slots.concat([{"day": "SAT", "start": "14:00", "end": "17:00", "raw": ""}]); }}>+ Add a time</button>
                </div>
                <label title="Michigan stores use built-in rules: groceries exempt, other goods 6%.">Sales tax rate outside Michigan (e.g. 0.07)<input aria-label="Tax rate" type="number" min="0" max="0.3" step="0.001" value={tax} onChange={lambda e: ChangeEvent { tax = e.target.value; }} /></label>
                <label>Estimated round-trip transport ($)<input aria-label="Transport cost" type="number" min="0" step="0.01" value={travel} onChange={lambda e: ChangeEvent { travel = e.target.value; }} /></label>
                <label title="Products must be labelled with every tag, e.g. vegan, gluten-free.">Dietary needs (e.g. vegan, gluten-free)<input aria-label="Dietary tags" value={dietary} onChange={lambda e: ChangeEvent { dietary = e.target.value; }} /></label>
                <button type="submit" className="go" disabled={busy}>Save preferences</button>
            </form>
            </section>
            <p className="attribution"><a href="https://www.geoapify.com/" target="_blank" rel="noreferrer">Powered by Geoapify</a> · © OpenStreetMap contributors. Historical product prices: Open Prices / Open Food Facts (ODbL). Optional current product data: Kroger.</p>
        </div>
        }}
        {if view == "plans" {
        <div>
        {if not workspace["profile"]["address"] {
            <AddressPicker workspace={workspace} busy={busy} operate={operate} auto={auto_locate} confirmed={on_address} />
        }}
        {if len(workspace["notices"]) > 0 {
            <details className="plan-fold"><summary>About these results</summary>{[<p key={str(i)}>{note}</p> for (i, note) in enumerate(workspace["notices"])]}</details>
        }}
        <PlanOptions plans={workspace["visit_plans"]} workspace={workspace} busy={busy} operate={operate} select={select} />
        {if workspace["profile"]["address"] { <VisitSearch workspace={workspace} busy={busy} operate={operate} /> }}
        {if workspace["profile"]["address"] {
            <details className="plan-fold"><summary>Have a delivery checkout quote? Add it to compare</summary><DeliveryQuotes workspace={workspace} busy={busy} operate={operate} /></details>
            <VisitHistory workspace={workspace} />
        }}
        </div>
        }}
    </section>;
}
