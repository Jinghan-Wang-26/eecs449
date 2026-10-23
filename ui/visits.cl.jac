"""Historical-evidence visit recommendations, with explicit unknowns and outcomes."""
def:pub VisitPlans(workspace: dict, busy: bool, operate: any) -> JsxElement {
    has radius: str = str(workspace["search_radius_m"]), acknowledged: dict = {};
    return <section id="store-visit-plans">
        <h3>Real-store shopping visits</h3>
        <p>Recommendations use your confirmed address and shopping list. Open Prices records are historical; current inventory, prices and opening hours need checking. Each option visits one store.</p>
        <label>Search radius<select aria-label="Visit search radius" value={radius} onChange={lambda e: ChangeEvent { radius = e.target.value; }}>
            <option value="500">500 m</option><option value="1000">1 km</option><option value="5000">5 km</option><option value="10000">10 km</option><option value="20000">20 km</option>
        </select></label>
        <button disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {"radius_m": radius}); }}>Recommend stores for my list</button>
        <p>Allow time for historical lookups and routes. Walking, cycling and driving are supported; public-transit schedules and rideshare estimates are unavailable.</p>
        {if workspace["visit_search"] {
            <p>{"Checked " + str(workspace["visit_search"]["checked_stores"]) + " of " + str(workspace["visit_search"]["nearby_count"]) + " nearby stores · " + workspace["visit_search"]["generated_at"]}</p>
        }}
        {[<article className="result-card" key={plan["key"]}>
            <h4>{plan["store"]["name"] + " · " + plan["status"]}</h4>
            <p>{plan["store"]["address"]}</p>
            <p>{"From: " + plan["origin_label"]}</p>
            <p>{plan["explanation"]}</p>
            {if plan["route"] {
                <p>{"Suggested weekly window: " + (plan["route"]["window"] or "No fitting free-time window") + " · Opening hours unverified"}</p>
                <p>{"Route estimate valid until " + plan["route"]["valid_until"]}</p>
                <a href={plan["navigation_url"]} target="_blank" rel="noreferrer">Directions from confirmed address</a>
            }}
            <p>{"Historical reference subtotal unavailable" if plan["reference_subtotal"] is None else "Historical reference: USD " + str(plan["reference_subtotal"]) + " for " + str(plan["priced_needs"]) + " of " + str(plan["need_count"]) + " needs; not today's basket total"}</p>
            <p>{"Known net product weight: " + ("unknown" if plan["known_net_weight_kg"] is None else str(plan["known_net_weight_kg"]) + " kg")}</p>
            {[<p key={warning}>{warning}</p> for warning in plan["warnings"]]}
            {[<p role="alert" key={blocker}>{blocker}</p> for blocker in plan["blockers"]]}
            {[<p key={note}>{note}</p> for note in plan["route_notices"]]}
            {if plan.get("review_reason") { <p role="alert">{plan["review_reason"]}</p> }}
            {[<div className="result-card" key={item["category"]}>
                <strong>{str(item["qty"]) + " packages × " + item["category"] + " · " + item["outcome"]}</strong>
                <p>{item["match_note"]}</p>
                {if item["evidence"] { <div>
                    <p>{item["evidence"]["name"] + " · " + item["evidence"]["brand"] + " · " + item["evidence"]["size_label"]}</p>
                    <p>{item["evidence"]["currency"] + " " + str(item["evidence"]["price"]) + " per " + item["evidence"]["price_per"] + " · Observed " + item["evidence"]["recorded_on"]}</p>
                    {if item["evidence"]["discounted"] { <p>{"Historical discount: " + (item["evidence"]["discount_type"] or "unspecified") + "; excluded from reference subtotal"}</p> }}
                    <a href={item["evidence"]["source_url"]} target="_blank" rel="noreferrer">Price record</a> · <a href={item["evidence"]["proof_url"]} target="_blank" rel="noreferrer">Supporting evidence</a>
                </div> }}
                {if plan.get("accepted_at") and plan["status"] in ["ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"] and item["outcome"] == "PENDING" {
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "PURCHASED"}); }}>Bought requested quantity</button>
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "NOT_FOUND"}); }}>Not found at visit</button>
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "outcome", "category": item["category"], "outcome": "SKIPPED"}); }}>Skip this item</button>
                }}
            </div> for item in plan["items"]]}
            {if plan["status"] == "PROPOSED" and plan["accept_allowed"] {
                <label><input type="checkbox" aria-label={"Acknowledge unknown prices and stock at " + plan["store"]["name"]} checked={acknowledged.get(plan["key"], False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(acknowledged)); next_values[plan["key"]] = e.target.checked; acknowledged = next_values; }} />I will confirm current prices, stock and opening hours before buying.</label>
                <button disabled={busy or not acknowledged.get(plan["key"], False)} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "accept", "acknowledge_unknowns": True}); }}>Accept store visit</button>
            }}
            {if plan["status"] != "COMPLETED" {
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "cancel"}); }}>Cancel store visit</button>
            }}
        </article> for plan in workspace["visit_plans"]]}
        <p>Historical evidence: <a href="https://prices.openfoodfacts.org/" target="_blank" rel="noreferrer">Open Prices / Open Food Facts</a> · <a href="https://opendatacommons.org/licenses/odbl/1-0/" target="_blank" rel="noreferrer">ODbL</a>. Route estimates: Geoapify / OpenStreetMap.</p>
    </section>;
}
