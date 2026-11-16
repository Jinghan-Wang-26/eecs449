"""Actionable trip details. Saved values and missing information share one place."""
import from .planview { short_address, window_label }

def:pub TripSetup(profile: dict, busy: bool, edit: any) -> JsxElement {
    rows = [
        {"id": "trip-start", "label": "Starting point", "value": short_address(profile["address"]) if profile["address"] else "Add an address", "ready": bool(profile["address"]), "mark": "↗"},
        {"id": "trip-time", "label": "Shopping time", "value": [window_label(w) for w in profile["free_windows"]].join(", ") or "Choose a free time", "ready": len(profile["free_windows"]) > 0, "mark": "◷"},
        {"id": "trip-transport", "label": "Getting there", "value": [m.slice(0, 1) + m.slice(1).lower() for m in profile["transport"]].join(" + ") or "Choose how to travel", "ready": len(profile["transport"]) > 0, "mark": "⇄"}
    ];
    count = len([r for r in rows if r["ready"]]);
    return <section className="trip-setup" aria-label="Trip details">
        <div className="setup-heading"><h3>Trip details</h3><span>{"Ready to compare" if count == 3 else str(3 - count) + (" detail to add" if count == 2 else " details to add")}</span></div>
        <div className="setup-grid">{[<button key={row["id"]} type="button" className={"setup-card ready" if row["ready"] else "setup-card missing"} disabled={busy} onClick={lambda e: MouseEvent { edit(row["id"]); }} aria-label={"Edit " + row["label"].lower()}>
            <span className="setup-mark" aria-hidden="true">{row["mark"]}</span>
            <span className="setup-copy"><small>{row["label"]}</small><b>{row["value"]}</b></span>
            <span className="setup-state" aria-hidden="true">{"✓" if row["ready"] else "+"}</span>
        </button> for row in rows]}</div>
    </section>;
}
