"""Retailer snapshots and historical visits with explicit unknowns and outcomes."""
import from .transit { TransitItinerary }
import from .itinerary { StoreItinerary }

def:pub VisitPlans(workspace: dict, busy: bool, operate: any) -> JsxElement {
    has radius: str = str(workspace["search_radius_m"]), acknowledged: dict = {}, delivery_ack: dict = {}, bought: dict = {}, paid: dict = {};
    return <section id="store-visit-plans">
        <h3>Real-store shopping visits</h3>
        <p>Recommendations use your confirmed address and shopping list. Supported retailers provide price and availability snapshots. Open Prices records remain historical. Missing data is Unknown; opening hours need checking. Compare single-store, two-store, delivery and mixed options when evidence is available.</p>
        <label>Search radius<select aria-label="Visit search radius" value={radius} onChange={lambda e: ChangeEvent { radius = e.target.value; }}>
            <option value="500">500 m</option><option value="1000">1 km</option><option value="5000">5 km</option><option value="10000">10 km</option><option value="20000">20 km</option>
        </select></label>
        <button disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {"radius_m": radius}); }}>Compare store options</button>
        <p>Allow time for retailer lookups, historical evidence and routes. Walking, cycling and driving are supported. Scheduled TheRide buses cover Ann Arbor/Ypsilanti; live arrivals and rideshare estimates are unavailable.</p>
        {if workspace["visit_search"].get("generated_at") {
            <p>{"Checked " + str(workspace["visit_search"]["checked_stores"]) + " of " + str(workspace["visit_search"]["nearby_count"]) + " nearby stores · " + workspace["visit_search"]["generated_at"]}</p>
        }}
        {[<article className="result-card" key={plan["key"]}>
            <div className="plan-title"><h4>{plan["store"]["name"]}</h4><span className="count-pill">{plan["status"].replace("_", " ")}</span></div>
            {if workspace.get("budget_notes", {}).get(plan["key"]) { <p className="budget-note">{workspace["budget_notes"][plan["key"]]}</p> }}
            <div className="plan-metrics"><div><small>{"Covered needs" if plan.get("delivery_quote") else "Retailer matches" if plan.get("kind") in ["CURRENT_STORE_VISIT","CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] else "Historical matches"}</small><strong>{str(plan["matched"]) + " / " + str(plan["need_count"])}</strong></div><div><small>Trip travel</small><strong>{str(plan["route"]["min"]) + " min" if plan["route"] else ("No store trip" if plan.get("kind") == "DELIVERY_VISIT" else "Unknown")}</strong></div><div><small>{"Merchandise subtotal" if plan.get("delivery_quote") else "Current item subtotal" if plan.get("kind") in ["CURRENT_STORE_VISIT","CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] else "Historical reference only"}</small><strong>{("USD " + str(plan["current_subtotal"]) if plan.get("current_subtotal", None) is not None else "Unknown") if plan.get("kind") in ["CURRENT_STORE_VISIT","CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] else ("USD " + str(plan["reference_subtotal"]) if plan["reference_subtotal"] is not None else "Unknown")}</strong></div></div>
            <p>{plan["store"]["address"]}</p>
            <p>{"From: " + plan["origin_label"]}</p>
            <p>{plan["explanation"]}</p>
            {[<span className="count-pill" key={label}>{label}</span> for label in plan.get("comparison_labels",[])]}
            {if plan.get("kind") in ["CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] {
                <p>{"Plan type: "+plan["kind"].replace("_"," ")+" · Active time: "+str(plan["active_min"])+" min"+(" · Compared "+str(plan["compared_options"])+" bounded options" if plan.get("compared_options",0) else " · Re-run recommendations to update comparison rankings")}</p>
                <p>{"Retailer items: USD "+str(plan["retail_subtotal"])+" · Delivery checkout total: "+("USD "+str(plan["delivery_total"]) if plan.get("delivery_total",None) is not None else "Not included / Unknown")}</p>
                if plan.get("savings_vs_single",None) is not None { <p>{"Compared with the same products at "+plan["baseline_store"]+": USD "+str(plan["savings_vs_single"])+" estimated savings (negative means more expensive)."}</p> }
                if plan.get("like_for_like",True) == False { <p>Product selections differ from the single-store baseline; no like-for-like savings claim is made.</p> }
            }}
            {if plan.get("delivery_quote") {
                <div className="source-note"><strong>USER-ENTERED DELIVERY QUOTE · NOT API VERIFIED</strong>
                    <p>{plan["delivery_quote"]["merchant"]+" · "+plan["delivery_quote"]["window_start"]+" → "+plan["delivery_quote"]["window_end"]}</p>
                    <p>{"Checkout evidence expires "+plan["delivery_quote"]["valid_until"]+". Accepting this plan does not reserve a delivery slot or place an order."}</p>
                    <a href={plan["delivery_quote"]["source_url"]} target="_blank" rel="noreferrer">Recheck and order on merchant site</a>
                </div>
            }}
            {if plan["route"] {
                <p>{"Suggested trip: " + (plan["route"]["window"] or "No fitting free-time window")}</p>
                if plan["route"].get("arrival_at") and not plan["route"].get("segments") {
                    <p>{"Arrive: " + plan["route"]["arrival_at"] + " · Leave store: " + plan["route"]["leave_store_at"] + " (" + plan["route"]["store_timezone"] + ")"}</p>
                }
                <p>{"Fits recorded regular opening hours; confirm holiday exceptions." if plan["route"].get("hours_status") == "REGULAR_HOURS_FIT" else "Opening hours not confirmed for this visit."}</p>
                <p>{"Route estimate valid until " + plan["route"]["valid_until"]}</p>
                <a href={plan["navigation_url"]} target="_blank" rel="noreferrer">Directions from confirmed address</a>
            }}
            {if plan["route"] and plan["route"].get("segments") { <StoreItinerary route={plan["route"]} /> } elif plan["route"] and plan["route"].get("scheduled_only") { <TransitItinerary route={plan["route"]} /> }}
            {if plan["store"].get("opening_hours") {
                <p>{"Recorded hours: " + plan["store"]["opening_hours"] + " · Source: "+plan["store"].get("hours_source","Geoapify / OpenStreetMap")+" · Retrieved " + plan["store"].get("hours_retrieved_at", "unknown")}</p>
            }}
            {if plan.get("kind") in ["CURRENT_STORE_VISIT","CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] {
                <p>{"Retailer snapshots checked " + plan.get("quote_checked_at", "Unknown") + " · " + str(plan.get("current_available", 0)) + " / " + str(plan["need_count"]) + " needs reported available"}</p>
                <p>{"Priced needs: " + str(plan.get("current_priced", 0)) + " / " + str(plan["need_count"]) + " · Estimated trip total: " + ("USD " + str(plan["estimated_total"]) if plan.get("estimated_total", None) is not None else "Unknown (missing prices, tax or transport cost)")}</p>
                <p>Retailer subtotals use regular package prices; delivery merchandise uses the entered checkout subtotal and discount. Estimated trip totals add known tax, transport and delivery charges. Stock levels do not guarantee the requested quantity or availability on a future visit.</p>
                if plan.get("quotes_expired", False) { <p role="alert">These quote snapshots expired. Refresh before relying on them.</p> }
                [<p role="alert" key={change}>{change}</p> for change in plan.get("quote_changes", [])];
                if not plan.get("accepted_at") {
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "refresh"}); }}>Refresh prices and availability</button>
                }
            } else {
            <p>{"Historical reference subtotal unavailable" if plan["reference_subtotal"] is None else "Historical reference: USD " + str(plan["reference_subtotal"]) + " for " + str(plan["priced_needs"]) + " of " + str(plan["need_count"]) + " needs; not today's basket total"}</p>
            }}
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
                {if item.get("store") { <p>{"Buy at "+item["store"]["name"]+" · "+item["store"]["address"]}</p> }}
                {if plan.get("kind") in ["CURRENT_STORE_VISIT","CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] {
                    if item.get("quote") {
                        <div>
                            <p>{item["quote"]["name"] + " · " + item["quote"]["brand"] + " · " + item["quote"]["size_label"]}</p>
                            <p>{"Regular package price: " + ("USD " + str(item["quote"]["price"]) if item["quote"]["price"] is not None else "Unknown") + " · Availability: " + item["quote"]["availability"].replace("_", " ")}</p>
                            <p>{"Item subtotal: " + ("USD " + str(item["current_amount"]) if item["current_amount"] is not None else "Unknown")}</p>
                            <p>{"Source: Kroger · Store " + item["quote"]["store_id"] + " · Product " + item["quote"]["external_id"] + " / " + item["quote"]["item_id"]}</p>
                            <p>{"Queried " + item["quote"]["observed_at"] + " · Refresh by " + item["quote"]["valid_until"]}</p>
                        </div>
                    } elif item.get("fulfillment") == "DELIVERY" { <p>{"Delivery via "+item["merchant"]+" · Included in entered checkout total; individual price and inventory are not API verified."}</p> } else { <p>Current price: Unknown · Availability: Unknown</p> }
                    if item.get("lookup_error") { <p role="alert">{item["lookup_error"]}</p> }
                }}
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
                <label><input type="checkbox" aria-label={"Acknowledge unknown prices and stock at " + plan["store"]["name"]} checked={acknowledged.get(plan["key"] + plan.get("quote_revision", ""), False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(acknowledged)); next_values[plan["key"] + plan.get("quote_revision", "")] = e.target.checked; acknowledged = next_values; }} />I reviewed the product matches and unknowns. I will check prices, stock and opening hours before buying.</label>
                if plan.get("delivery_quote") {
                    <label><input type="checkbox" aria-label="Reconfirm delivery checkout" checked={delivery_ack.get(plan["key"]+plan.get("quote_revision",""),False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(delivery_ack)); next_values[plan["key"]+plan.get("quote_revision","")] = e.target.checked; delivery_ack = next_values; }} />I rechecked merchant checkout: this exact basket, address, all charges and delivery window still apply. I will place the order myself.</label>
                }
                <button disabled={busy or (plan.get("delivery_quote") and not delivery_ack.get(plan["key"]+plan.get("quote_revision",""),False)) or not acknowledged.get(plan["key"] + plan.get("quote_revision", ""), False)} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "accept", "acknowledge_unknowns": True, "quote_revision": plan.get("quote_revision", ""), "delivery_reconfirmed": delivery_ack.get(plan["key"]+plan.get("quote_revision",""),False)}); }}>Recheck and accept store visit</button>
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
        <p>Historical evidence: <a href="https://prices.openfoodfacts.org/" target="_blank" rel="noreferrer">Open Prices / Open Food Facts</a> · <a href="https://opendatacommons.org/licenses/odbl/1-0/" target="_blank" rel="noreferrer">ODbL</a>. Walking and road routes: Geoapify / OpenStreetMap. Scheduled buses: TheRide GTFS.</p>
    </section>;
}
