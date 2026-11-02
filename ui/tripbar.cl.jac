"""Trip summary band, rolling numbers and the List → Options → Route → Shop stage nav."""

"""Digits roll from the previous value to the new one. Screen readers get the
final value only; the rolling columns are hidden from them."""
def:pub Odometer(value: str) -> JsxElement {
    has shown: str = value, previous: str = value, rolled: bool = True;
    can with (value) entry {
        if value == shown { return; }
        previous = shown; shown = value; rolled = False;
        frame = window.requestAnimationFrame(lambda { window.requestAnimationFrame(lambda { rolled = True; }); });
        return lambda { window.cancelAnimationFrame(frame); };
    }
    width = Math.max(len(previous), len(shown));
    now_chars = shown.padStart(width, " ").split("");
    old_chars = previous.padStart(width, " ").split("");
    digits = "0123456789".split("");
    return <span className="odo">
        <span className="sr-only">{shown}</span>
        <span aria-hidden="true" className="odo">{[
            (<span key={str(i)} className="odo-col"><span style={{"transform": "translateY(-" + str(1.15 * Number(ch if rolled or not ("0" <= old_chars[i] and old_chars[i] <= "9") else old_chars[i])) + "em)", "transitionDelay": str(i * 30) + "ms"}}>{[<i key={d}>{d}</i> for d in digits]}</span></span>)
            if "0" <= ch and ch <= "9" else <span key={str(i)}>{("" if i < width - len(shown) else "\u00a0") if ch == " " else ch}</span>
            for (i, ch) in enumerate(now_chars)
        ]}</span>
    </span>;
}

"""stats: [{"id", "label", "value", "unit", "tone"}]; prefs: [{"id", "text"}]."""
def:pub TripBar(title: str, sub: str, pill: str, tone: str, stats: list, prefs: list, edit: any, first_use: bool = False) -> JsxElement {
    words = ["Tell", "me", "what", "you", "need.", "I'll", "plan", "the", "trip."];
    return <section className="trip-bar" aria-label="Trip summary">
        <div className="trip-top">
            <div>
                {if first_use {
                    <h2 className="kinetic" aria-label="Tell me what you need. I'll plan the trip.">{[(<span key={str(i)} aria-hidden="true" style={{"animationDelay": str(i * 90) + "ms"}}>{(<em>{w}</em>) if i >= 5 else w}{" "}</span>) for (i, w) in enumerate(words)]}</h2>
                } else {
                    <h2>{title}</h2>
                }}
                <div className="trip-sub">{sub}</div>
            </div>
            <div className="trip-side">
                <span className={"trip-pill " + tone}>{pill}</span>
            </div>
        </div>
        {if len(stats) > 0 {
            <div className="trip-stats">{[<div key={s["id"]} id={"chg-" + s["id"]} className={"trip-stat " + s.get("tone", "")}><small>{s["label"]}</small><span className="value"><Odometer value={s["value"]} />{if s.get("unit", None) { <span className="unit">{s["unit"]}</span> }}</span></div> for s in stats]}</div>
        }}
        <div className="trip-prefs">
            {[<span key={p["id"]} id={"chg-" + p["id"]}>{p["text"]}</span> for p in prefs]}
            <button type="button" onClick={lambda e: MouseEvent { edit(); }}>Edit preferences</button>
        </div>
    </section>;
}

def:pub StageNav(stage: str, progress: int, go: any) -> JsxElement {
    stages = [{"id": "list", "label": "List"}, {"id": "options", "label": "Options"}, {"id": "route", "label": "Route"}, {"id": "shop", "label": "Shop"}];
    ids = ["list", "options", "route", "shop"];
    current = ids.indexOf(stage);

    def key(e: any, idx: int) -> None {
        nxt = idx;
        if e.key == "ArrowRight" { nxt = (idx + 1) % 4; }
        elif e.key == "ArrowLeft" { nxt = (idx + 3) % 4; }
        elif e.key == "Home" { nxt = 0; }
        elif e.key == "End" { nxt = 3; }
        else { return; }
        e.preventDefault();
        go(ids[nxt]);
        el = document.getElementById("stage-" + ids[nxt]);
        if el { el.focus(); }
    }

    return <nav className="stage-nav" role="tablist" aria-label="Trip stages">
        {if current >= 0 { <i className="stage-ind" aria-hidden="true" style={{"left": "calc(4px + " + str(current) + " * (100% - 8px) / 4)"}}></i> }}
        {[<button key={s["id"]} id={"stage-" + s["id"]} role="tab" type="button" aria-selected={stage == s["id"]} aria-controls="stage-panel" tabIndex={0 if stage == s["id"] or (current < 0 and i == 0) else -1}
            className={"done" if i < progress and stage != s["id"] else ""} onKeyDown={lambda e: any { key(e, i); }} onClick={lambda e: MouseEvent { go(s["id"]); }}>
            <em>{"✓" if i < progress and stage != s["id"] else str(i + 1)}</em>{s["label"]}</button> for (i, s) in enumerate(stages)]}
    </nav>;
}
