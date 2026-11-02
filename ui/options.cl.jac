"""Options stage: one recommended plan, a few one-line alternatives, and folded
plans that cannot be accepted. The reason sentence comes before the labels."""
import from .planview { facts, recommended, reason_sentence, money, duration, kg, trip_segments, delivered_items, current_kind }
import from .visits { VisitDetails }

def:pub TimeStrip(plan: dict) -> JsxElement {
    segments = trip_segments(plan);
    if len(segments) == 0 { return <span></span>; }
    return <div className="time-strip" aria-hidden="true">{[<i key={str(i)} className={seg["kind"]} style={{"flex": str(seg["min"]), "animationDelay": str(i * 50) + "ms"}}></i> for (i, seg) in enumerate(segments)]}</div>;
}

"""Whether any item has a current quote or a historical match; a route alone verifies nothing."""
def product_evidence(plan: dict) -> bool {
    return plan.get("current_available", None) or plan.get("matched", None) or len([item for item in plan.get("items", []) if item.get("quote", None) or item.get("evidence", None)]) > 0;
}

def:pub Metrics(row: dict, carry_limit: any) -> JsxElement {
    over = row["weight"] is not None and carry_limit is not None and row["weight"] > carry_limit;
    return <div className="metrics">
        {if row["total"] is None and row.get("items", None) is not None {
            <div><small title="The full total needs your round-trip transport cost (bus fare) in Preferences.">{("Items + tax" if row.get("items_taxed", False) else "Items") + " · fare unknown"}</small><strong id="chg-total">{money(row["items"])}</strong></div>
        } else {
            <div className={"unknown" if row["total"] is None else ""}><small>Estimated total</small><strong id="chg-total">{money(row["total"])}</strong></div>
        }}
        <div className={"unknown" if row["minutes"] is None else ""}><small>Active time</small><strong>{duration(row["minutes"])}</strong></div>
        <div className={"bad" if over else ("unknown" if row["weight"] is None or row.get("weight_missing", 0) > 0 else "ok")}><small>{"Over your " + kg(carry_limit) + " limit" if over else ("You carry at least" if row["weight"] is not None and row.get("weight_missing", 0) > 0 else "You carry")}</small><strong>{kg(row["weight"])}</strong></div>
    </div>;
}

def:pub CostBreakdown(plan: dict, profile: dict) -> JsxElement {
    return <div className="breakdown">
        {if plan.get("retail_subtotal", None) is not None { <span>{"Store items "}<b>{money(plan["retail_subtotal"])}</b></span> } elif plan.get("current_subtotal", None) is not None { <span>{"Store items "}<b>{money(plan["current_subtotal"])}</b></span> }}
        {if plan.get("delivery_quote", None) { <span>{"Delivery checkout "}<b>{money(plan.get("delivery_total", None))}</b>{" "}<span className="ev user">your entered quote</span></span> }}
        {if plan.get("transport_estimate", None) is not None { <span>{"Transport "}<b>{money(plan["transport_estimate"])}</b>{if plan["transport_estimate"] > 0 and profile.get("transport_cost", -1) >= 0 { <span>{" "}<span className="ev user">your estimate</span></span> }}</span> } elif plan.get("route", None) { <span>{"Transport "}<b>Unknown</b>{" · "}<button type="button" className="text-button" onClick={lambda e: MouseEvent { window.dispatchEvent(new(CustomEvent, "cartcompass-view", {"detail": "profile"})); }}>add your fare</button></span> }}
        {if plan.get("tax_basis", None) in ["STATE_RULES", "YOUR_RATE", "MIXED"] {
            <span>{"Tax "}<b>{money(plan["tax_estimate"])}</b>{" "}<span className={"ev" + ("" if plan["tax_basis"] == "STATE_RULES" else " user")}>{"estimate · " + plan["tax_note"]}</span></span>
        } elif plan.get("tax_basis", None) == "UNKNOWN" {
            <span>{"Tax "}<b>Unknown</b>{" · "}<button type="button" className="text-button" title={plan["tax_note"]} onClick={lambda e: MouseEvent { window.dispatchEvent(new(CustomEvent, "cartcompass-view", {"detail": "profile"})); }}>add your tax rate</button></span>
        } elif plan.get("tax_basis", None) is None and profile["tax_rate"] >= 0 {
            <span>{"Tax rate "}<b>{str(Math.round(profile["tax_rate"] * 1000) / 10) + "%"}</b>{" "}<span className="ev user">your estimate</span></span>
        }}
        {if not current_kind(plan) { <span className="ev">Historical reference only · not today's price</span> }}
    </div>;
}

def:pub PlanOptions(plans: list, workspace: dict, busy: bool, operate: any, select: any) -> JsxElement {
    rows =[facts(plan) for plan in plans if plan["status"] in ["PROPOSED", "NEEDS_REVIEW"]];
    best = recommended(rows);
    others = [row for row in rows if row["eligible"] and (best is None or row["key"] != best["key"])];
    # Stores with only a route and no product data say nothing about the basket; fold them.
    eligible = [row for row in others if product_evidence(row["plan"])];
    unknown = [row for row in others if not product_evidence(row["plan"])];
    review = [row for row in rows if row["status"] == "NEEDS_REVIEW"];
    blocked = [row for row in rows if not row["eligible"] and row["status"] != "NEEDS_REVIEW"];
    profile = workspace["profile"];
    limit = profile["carry_limit_kg"];
    groups = {};
    for row in blocked {
        reason = row["blockers"][0] if len(row["blockers"]) > 0 else "Missing prices or route evidence";
        if reason not in groups { groups[reason] = []; }
        groups[reason].append(row);
    }
    if len(rows) == 0 { return <span></span>; }
    return <section id="chg-plans" aria-label="Shopping options">
        <div className="stage-head"><h3>{str(len(rows)) + (" way" if len(rows) == 1 else " ways") + " to shop"}</h3><small>{str(len([r for r in rows if r["eligible"]])) + " fit your limits"}</small></div>
        {if best {
            <article className="plan-best" onMouseMove={lambda e: any { r = e.currentTarget.getBoundingClientRect(); e.currentTarget.style.setProperty("--mx", str(e.clientX - r.left) + "px"); e.currentTarget.style.setProperty("--my", str(e.clientY - r.top) + "px"); }}>
                <span className="plan-kicker">{"Recommended" if product_evidence(best["plan"]) else "Route fits · products not confirmed"}</span>
                <span className="plan-name">{best["title"]}</span>
                {if reason_sentence(best, rows, len(blocked)) { <div className="plan-why">{reason_sentence(best, rows, len(blocked))}</div> }}
                <Metrics row={best} carry_limit={limit} />
                <TimeStrip plan={best["plan"]} />
                <CostBreakdown plan={best["plan"]} profile={profile} />
                <div>{[<span key={label} className="label-chip">{label}</span> for label in best["labels"]]}
                    {if best["plan"].get("quote_checked_at", None) { <span className="ev">{(best["plan"]["store"]["name"] if best["plan"].get("store", None) else "Retailer") + " · checked " + best["plan"]["quote_checked_at"].slice(11, 16) + " · stock not reserved"}</span> }}
                </div>
                {if workspace.get("budget_notes", {}).get(best["key"]) { <p className="budget-note">{workspace["budget_notes"][best["key"]]}</p> }}
                <div className="cta-row"><details><summary>Full plan details</summary><VisitDetails plan={best["plan"]} /></details>
                    <button className="primary cta" onClick={lambda e: MouseEvent { select(best["key"]); }}>Review route →</button></div>
            </article>
        }}
        {[<div key={row["key"]} className="plan-alt">
            <span><b>{row["title"]}</b><br /><small>{(row["labels"].join(" · ") or "Alternative") + (" · " + str(len(delivered_items(row["plan"]))) + " delivered" if len(delivered_items(row["plan"])) > 0 else "")}</small></span>
            <b className="v">{money(row["total"]) if row["total"] is not None or row.get("items", None) is None else money(row["items"]) + " items"}</b>
            <span className="num hide-narrow">{duration(row["minutes"])}</span>
            <span className="num hide-narrow">{kg(row["weight"])}</span>
            <button onClick={lambda e: MouseEvent { select(row["key"]); }}>Choose</button>
        </div> for row in eligible.slice(0, 3)]}
        {if len(unknown) > 0 {
            <details className="plan-fold"><summary>{str(len(unknown)) + (" nearby store" if len(unknown) == 1 else " nearby stores") + " without price or stock data"}</summary>
                <p>The route fits, but nothing is known about their products. Choose one only if you want to check it in person.</p>
                <ul>{[<li key={row["key"]}>{row["title"] + " · " + duration(row["minutes"]) + " "}<button type="button" className="text-button" onClick={lambda e: MouseEvent { select(row["key"]); }}>Choose</button></li> for row in unknown]}</ul>
            </details>
        }}
        {[<div key={row["key"]} className="plan-alt">
            <span><b>{row["title"]}</b><br /><small>Needs a fresh check before you can accept it</small></span>
            <b className="v">{money(row["total"]) if row["total"] is not None or row.get("items", None) is None else money(row["items"]) + " items"}</b>
            <span className="num hide-narrow">{duration(row["minutes"])}</span>
            <span className="num hide-narrow">{kg(row["weight"])}</span>
            <button onClick={lambda e: MouseEvent { select(row["key"]); }}>Review</button>
        </div> for row in review]}
        {[<details key={reason} className="plan-fold"><summary>{str(len(groups[reason])) + (" option can't" if len(groups[reason]) == 1 else " options can't") + " be accepted: " + reason}</summary>
            <ul>{[<li key={row["key"]}>{row["title"] + " · " + money(row["total"]) + " · " + duration(row["minutes"]) + " · " + kg(row["weight"])}<details><summary>Details</summary><VisitDetails plan={row["plan"]} /></details></li> for row in groups[reason]]}</ul>
        </details> for reason in Object.keys(groups)]}
    </section>;
}
