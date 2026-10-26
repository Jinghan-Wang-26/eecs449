"""Historical-evidence visit recommendations, with explicit unknowns and outcomes."""
def:pub VisitPlans(workspace: dict, busy: bool, operate: any) -> JsxElement {
    has radius: str = str(workspace["search_radius_m"]), acknowledged: dict = {}, bought: dict = {}, paid: dict = {};
    return <section id="store-visit-plans">
        <h3>Real-store shopping visits</h3>
        <p>Recommendations use your confirmed address and shopping list. Open Prices records are historical; current inventory, prices and opening hours need checking. Each option visits one store.</p>
        <label>Search radius<select aria-label="Visit search radius" value={radius} onChange={lambda e: ChangeEvent { radius = e.target.value; }}>
            <option value="500">500 m</option><option value="1000">1 km</option><option value="5000">5 km</option><option value="10000">10 km</option><option value="20000">20 km</option>
        </select></label>
        <button disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {"radius_m": radius}); }}>Recommend stores for my list</button>
        <p>Allow time for historical lookups and routes. Walking, cycling and driving are supported; public-transit schedules and rideshare estimates are unavailable.</p>
        {if workspace["visit_search"].get("generated_at") {
            <p>{"Checked " + str(workspace["visit_search"]["checked_stores"]) + " of " + str(workspace["visit_search"]["nearby_count"]) + " nearby stores · " + workspace["visit_search"]["generated_at"]}</p>
        }}
        {[<article className="result-card" key={plan["key"]}>
            <div className="plan-title"><h4>{plan["store"]["name"]}</h4><span className="count-pill">{plan["status"].replace("_", " ")}</span></div>
            <div className="plan-metrics"><div><small>Historical matches</small><strong>{str(plan["matched"]) + " / " + str(plan["need_count"])}</strong></div><div><small>Round-trip travel</small><strong>{str(plan["route"]["min"]) + " min" if plan["route"] else "Unknown"}</strong></div><div><small>Historical reference only</small><strong>{"USD " + str(plan["reference_subtotal"]) if plan["reference_subtotal"] is not None else "Unknown"}</strong></div></div>
            <p>{plan["store"]["address"]}</p>
            <p>{"From: " + plan["origin_label"]}</p>
            <p>{plan["explanation"]}</p>
            {if plan["route"] {
                <p>{"Suggested trip: " + (plan["route"]["window"] or "No fitting free-time window")}</p>
                if plan["route"].get("arrival_at") {
                    <p>{"Arrive: " + plan["route"]["arrival_at"] + " · Leave store: " + plan["route"]["leave_store_at"] + " (" + plan["route"]["store_timezone"] + ")"}</p>
                }
                <p>{"Fits recorded regular opening hours; confirm holiday exceptions." if plan["route"].get("hours_status") == "REGULAR_HOURS_FIT" else "Opening hours not confirmed for this visit."}</p>
                <p>{"Route estimate valid until " + plan["route"]["valid_until"]}</p>
                <a href={plan["navigation_url"]} target="_blank" rel="noreferrer">Directions from confirmed address</a>
            }}
            {if plan["store"].get("opening_hours") {
                <p>{"Recorded hours: " + plan["store"]["opening_hours"] + " · Source: Geoapify / OpenStreetMap · Retrieved " + plan["store"].get("hours_retrieved_at", "unknown")}</p>
            }}
            <p>{"Historical reference subtotal unavailable" if plan["reference_subtotal"] is None else "Historical reference: USD " + str(plan["reference_subtotal"]) + " for " + str(plan["priced_needs"]) + " of " + str(plan["need_count"]) + " needs; not today's basket total"}</p>
            <p>{"Known net product weight: " + ("unknown" if plan["known_net_weight_kg"] is None else str(plan["known_net_weight_kg"]) + " kg")}</p>
            <details><summary>Price, coverage & carrying limitations</summary>{[<p key={warning}>{warning}</p> for warning in plan["warnings"]]}</details>
            {[<p role="alert" key={blocker}>{blocker}</p> for blocker in plan["blockers"]]}
            {[<p key={note}>{note}</p> for note in plan["route_notices"]]}
            {if plan.get("review_reason") { <p role="alert">{plan["review_reason"]}</p> }}
            {[<div className="result-card" key={item["category"]}>
                <strong>{str(item["qty"]) + " packages × " + item["category"] + " · " + item["outcome"]}</strong>
                {if item.get("bought_qty", None) is not None {
                    <p>{"Bought " + str(item["bought_qty"]) + " · Still needed " + str(item["remaining_qty"]) + " · Actual paid: " + ("not recorded" if item.get("actual_paid", None) is None else "USD " + str(item["actual_paid"]))}</p>
                }}
                <p>{item["match_note"]}</p>
                {if item["evidence"] { <div>
                    <p>{item["evidence"]["name"] + " · " + item["evidence"]["brand"] + " · " + item["evidence"]["size_label"]}</p>
                    <p>{item["evidence"]["currency"] + " " + str(item["evidence"]["price"]) + " per " + item["evidence"]["price_per"] + " · Observed " + item["evidence"]["recorded_on"]}</p>
                    {if item["evidence"]["discounted"] { <p>{"Historical discount: " + (item["evidence"]["discount_type"] or "unspecified") + "; excluded from reference subtotal"}</p> }}
                    <a href={item["evidence"]["source_url"]} target="_blank" rel="noreferrer">Price record</a> · <a href={item["evidence"]["proof_url"]} target="_blank" rel="noreferrer">Supporting evidence</a>
                </div> }}
                {if plan.get("accepted_at") and plan["status"] in ["ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"] and item["outcome"] == "PENDING" {
                    <label>Packages bought<input type="number" min="1" max={str(item["qty"])} step="1" aria-label={"Packages bought: " + item["category"]} value={bought.get(plan["key"] + item["category"], str(item["qty"]))} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(bought)); next_values[plan["key"] + item["category"]] = e.target.value; bought = next_values; }} /></label>
                    <label>Actual amount paid (USD, optional)<input type="number" min="0" step="0.01" aria-label={"Actual amount paid: " + item["category"]} value={paid.get(plan["key"] + item["category"], "")} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(paid)); next_values[plan["key"] + item["category"]] = e.target.value; paid = next_values; }} /></label>
                    <button disabled={busy} onClick={lambda e: MouseEvent { count = bought.get(plan["key"] + item["category"], str(item["qty"])); operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "PURCHASED" if Number(count) == item["qty"] else "PARTIAL", "bought_qty": count, "actual_paid": paid.get(plan["key"] + item["category"], "")}); }}>Record purchase</button>
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "NOT_FOUND"}); }}>Not found at visit</button>
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "SKIPPED"}); }}>Skip this item</button>
                }}
            </div> for item in plan["items"]]}
            {if plan.get("reported_paid_usd", None) is not None {
                <p>{"Reported spending: USD " + str(plan["reported_paid_usd"]) + " across " + str(plan["paid_items_count"]) + " items with entered amounts. Unrecorded amounts and transport are excluded."}</p>
            }}
            {if plan["status"] == "COMPLETED" and len([item for item in plan["items"] if item.get("remaining_qty", 0) > 0]) > 0 {
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {"radius_m": radius}); }}>Plan remaining shopping needs</button>
            }}
            {if plan["status"] == "PROPOSED" and plan["accept_allowed"] {
                <label><input type="checkbox" aria-label={"Acknowledge unknown prices and stock at " + plan["store"]["name"]} checked={acknowledged.get(plan["key"], False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(acknowledged)); next_values[plan["key"]] = e.target.checked; acknowledged = next_values; }} />I will confirm current prices, stock and opening hours before buying.</label>
                <button disabled={busy or not acknowledged.get(plan["key"], False)} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "accept", "acknowledge_unknowns": True}); }}>Accept store visit</button>
            }}
            {if plan["status"] != "COMPLETED" {
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "cancel"}); }}>Cancel store visit</button>
            }}
        </article> for plan in workspace["visit_plans"]]}
        {if len(workspace.get("visit_history", [])) > 0 {
            <details>
                <summary>Previous visits and purchases</summary>
                {[<article key={old["key"]}>
                    <h4>{old["store"]["name"] + " · " + old["status"]}</h4>
                    <p>{old["created_at"]}</p>
                    {[<p key={item["category"]}>{item["category"] + " · " + item["outcome"] + " · Bought: " + str(item.get("bought_qty", "not recorded")) + " · Paid: " + ("not recorded" if item.get("actual_paid", None) is None else "USD " + str(item["actual_paid"]))}</p> for item in old["items"]]}
                </article> for old in workspace.get("visit_history", [])]}
            </details>
        }}
        <p>Historical evidence: <a href="https://prices.openfoodfacts.org/" target="_blank" rel="noreferrer">Open Prices / Open Food Facts</a> · <a href="https://opendatacommons.org/licenses/odbl/1-0/" target="_blank" rel="noreferrer">ODbL</a>. Route estimates: Geoapify / OpenStreetMap.</p>
    </section>;
}
