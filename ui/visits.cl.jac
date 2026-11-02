"""Retailer snapshots and historical visits with explicit unknowns and outcomes."""
import from .transit { TransitItinerary }
import from .itinerary { StoreItinerary }
import from .planview { current_kind, clock, short_address }

"""Search radius and the button that compares store options for the current list."""
def:pub VisitSearch(workspace: dict, busy: bool, operate: any) -> JsxElement {
    has radius: str = str(workspace["search_radius_m"]);
    return <section id="store-visit-plans" className="visit-search">
        <div className="cta-row">
            <span>{"From " + (short_address(workspace["profile"]["address"]) if workspace["profile"]["address"] else "your address") + " · within "}<select aria-label="Visit search radius" className="inline-select" value={radius} onChange={lambda e: ChangeEvent { radius = e.target.value; }}>
                <option value="500">500 m</option><option value="1000">1 km</option><option value="5000">5 km</option><option value="10000">10 km</option><option value="20000">20 km</option>
            </select>{" · "}<button type="button" className="text-button" onClick={lambda e: MouseEvent { window.dispatchEvent(new(CustomEvent, "cartcompass-view", {"detail": "profile"})); }}>Change address</button></span>
            <button className={"primary cta" if len(workspace["visit_plans"]) == 0 else ""} disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {"radius_m": radius}); }}>{"Compare store options" if len(workspace["visit_plans"]) == 0 else "Compare again"}</button>
        </div>
        {if workspace["visit_search"].get("generated_at", None) {
            <p className="search-note">{"Checked " + str(workspace["visit_search"]["checked_stores"]) + " of " + str(workspace["visit_search"]["nearby_count"]) + " nearby stores · scheduled buses, not live arrivals"}</p>
        }}
    </section>;
}

"""Everything the server knows about one visit plan, read-only. Actions live in AcceptPanel and InStore."""
def:pub VisitDetails(plan: dict) -> JsxElement {
    return <div className="visit-details">
        <div className="plan-metrics"><div><small>{"Covered needs" if plan.get("delivery_quote", None) else "Retailer matches" if current_kind(plan) else "Historical matches"}</small><strong>{str(plan["matched"]) + " / " + str(plan["need_count"])}</strong></div><div><small>Trip travel</small><strong>{str(plan["route"]["min"]) + " min" if plan["route"] else ("No store trip" if plan.get("kind", None) == "DELIVERY_VISIT" else "Unknown")}</strong></div><div><small>{"Merchandise subtotal" if plan.get("delivery_quote", None) else "Current item subtotal" if current_kind(plan) else "Historical reference only"}</small><strong>{("USD " + str(plan["current_subtotal"]) if plan.get("current_subtotal", None) is not None else "Unknown") if current_kind(plan) else ("USD " + str(plan["reference_subtotal"]) if plan["reference_subtotal"] is not None else "Unknown")}</strong></div></div>
        <p>{plan["store"]["address"]}</p>
        <p>{"From: " + plan["origin_label"]}</p>
        <p>{plan["explanation"]}</p>
        {if plan.get("kind", None) in ["CURRENT_MULTI_VISIT","DELIVERY_VISIT","MIXED_VISIT"] {
            <p>{"Plan type: "+plan["kind"].replace("_"," ")+" · Active time: "+str(plan["active_min"])+" min"+(" · Compared "+str(plan["compared_options"])+" bounded options" if plan.get("compared_options",0) else " · Re-run recommendations to update comparison rankings")}</p>
            <p>{"Retailer items: USD "+str(plan["retail_subtotal"])+" · Delivery checkout total: "+("USD "+str(plan["delivery_total"]) if plan.get("delivery_total",None) is not None else "Not included / Unknown")}</p>
            if plan.get("savings_vs_single",None) is not None { <p>{"Compared with the same products at "+plan["baseline_store"]+": USD "+str(plan["savings_vs_single"])+" estimated savings (negative means more expensive)."}</p> }
            if plan.get("like_for_like",True) == False { <p>Product selections differ from the single-store baseline; no like-for-like savings claim is made.</p> }
        }}
        {if plan.get("delivery_quote", None) {
            <div className="source-note"><strong>USER-ENTERED DELIVERY QUOTE · NOT API VERIFIED</strong>
                <p>{plan["delivery_quote"]["merchant"]+" · "+plan["delivery_quote"]["window_start"]+" → "+plan["delivery_quote"]["window_end"]}</p>
                <p>{"Checkout evidence expires "+plan["delivery_quote"]["valid_until"]+". Accepting this plan does not reserve a delivery slot or place an order."}</p>
                <a href={plan["delivery_quote"]["source_url"]} target="_blank" rel="noreferrer">Recheck and order on merchant site</a>
            </div>
        }}
        {if plan["route"] {
            <p>{"Suggested trip: " + (plan["route"]["window"] or "No fitting free-time window")}</p>
            if plan["route"].get("arrival_at", None) and not plan["route"].get("segments", None) {
                <p>{"Arrive: " + plan["route"]["arrival_at"] + " · Leave store: " + plan["route"]["leave_store_at"] + " (" + plan["route"]["store_timezone"] + ")"}</p>
            }
            <p>{"Fits recorded regular opening hours; confirm holiday exceptions." if plan["route"].get("hours_status", None) == "REGULAR_HOURS_FIT" else "Opening hours not confirmed for this visit."}</p>
            <p>{"Route estimate valid until " + plan["route"]["valid_until"]}</p>
            <a href={plan["navigation_url"]} target="_blank" rel="noreferrer">Directions from confirmed address</a>
        }}
        {if plan["route"] and plan["route"].get("segments", None) { <StoreItinerary route={plan["route"]} /> } elif plan["route"] and plan["route"].get("scheduled_only", None) { <TransitItinerary route={plan["route"]} /> }}
        {if plan["store"].get("opening_hours", None) {
            <p>{"Recorded hours: " + plan["store"]["opening_hours"] + " · Source: "+plan["store"].get("hours_source","Geoapify / OpenStreetMap")+" · Retrieved " + plan["store"].get("hours_retrieved_at", "unknown")}</p>
        }}
        {if current_kind(plan) {
            <p>{"Retailer snapshots checked " + plan.get("quote_checked_at", "Unknown") + " · " + str(plan.get("current_available", 0)) + " / " + str(plan["need_count"]) + " needs reported available"}</p>
            <p>{"Priced needs: " + str(plan.get("current_priced", 0)) + " / " + str(plan["need_count"]) + " · Estimated trip total: " + ("USD " + str(plan["estimated_total"]) if plan.get("estimated_total", None) is not None else "Unknown (missing prices, tax or transport cost)")}</p>
            <p>Retailer subtotals use regular package prices; delivery merchandise uses the entered checkout subtotal and discount. Estimated trip totals add known tax, transport and delivery charges. Stock levels do not guarantee the requested quantity or availability on a future visit.</p>
        } else {
            <p>{"Historical reference subtotal unavailable" if plan["reference_subtotal"] is None else "Historical reference: USD " + str(plan["reference_subtotal"]) + " for " + str(plan["priced_needs"]) + " of " + str(plan["need_count"]) + " needs; not today's basket total"}</p>
        }}
        <p>{"Known net product weight: " + ("unknown" if plan["known_net_weight_kg"] is None else str(plan["known_net_weight_kg"]) + " kg")}</p>
        <details><summary>Price, coverage & carrying limitations</summary>{[<p key={warning}>{warning}</p> for warning in plan["warnings"]]}</details>
        {[<p role="alert" key={blocker}>{blocker}</p> for blocker in plan["blockers"]]}
        {[<p key={note}>{note}</p> for note in plan["route_notices"]]}
        {[<div className="result-card" key={item["category"]}>
            <strong>{str(item["qty"]) + " packages × " + item["category"] + " · " + item["outcome"]}</strong>
            {if item.get("bought_qty", None) is not None {
                <p>{"Bought " + str(item["bought_qty"]) + " · Still needed " + str(item["remaining_qty"]) + " · Actual paid: " + ("not recorded" if item.get("actual_paid", None) is None else "USD " + str(item["actual_paid"]))}</p>
            }}
            <p>{item["match_note"]}</p>
            {if item.get("store", None) { <p>{"Buy at "+item["store"]["name"]+" · "+item["store"]["address"]}</p> }}
            {if current_kind(plan) {
                if item.get("quote", None) {
                    <div>
                        <p>{item["quote"]["name"] + " · " + item["quote"]["brand"] + " · " + item["quote"]["size_label"]}</p>
                        <p>{"Regular package price: " + ("USD " + str(item["quote"]["price"]) if item["quote"]["price"] is not None else "Unknown") + " · Availability: " + item["quote"]["availability"].replace("_", " ")}</p>
                        <p>{"Item subtotal: " + ("USD " + str(item["current_amount"]) if item["current_amount"] is not None else "Unknown")}</p>
                        <p>{"Source: Kroger · Store " + item["quote"]["store_id"] + " · Product " + item["quote"]["external_id"] + " / " + item["quote"]["item_id"]}</p>
                        <p>{"Queried " + item["quote"]["observed_at"] + " · Refresh by " + item["quote"]["valid_until"]}</p>
                    </div>
                } elif item.get("fulfillment", None) == "DELIVERY" { <p>{"Delivery via "+item["merchant"]+" · Included in entered checkout total; individual price and inventory are not API verified."}</p> } else { <p>Current price: Unknown · Availability: Unknown</p> }
                if item.get("lookup_error", None) { <p role="alert">{item["lookup_error"]}</p> }
            }}
            {if item["evidence"] { <div>
                <p>{item["evidence"]["name"] + " · " + item["evidence"]["brand"] + " · " + item["evidence"]["size_label"]}</p>
                <p>{item["evidence"]["currency"] + " " + str(item["evidence"]["price"]) + " per " + item["evidence"]["price_per"] + " · Observed " + item["evidence"]["recorded_on"]}</p>
                {if item["evidence"]["discounted"] { <p>{"Historical discount: " + (item["evidence"]["discount_type"] or "unspecified") + "; excluded from reference subtotal"}</p> }}
                <a href={item["evidence"]["source_url"]} target="_blank" rel="noreferrer">Price record</a> · <a href={item["evidence"]["proof_url"]} target="_blank" rel="noreferrer">Supporting evidence</a>
            </div> }}
        </div> for item in plan["items"]]}
        {if plan.get("reported_paid_usd", None) is not None {
            <p>{"Reported spending: USD " + str(plan["reported_paid_usd"]) + " across " + str(plan["paid_items_count"]) + " items with entered amounts. Unrecorded amounts and transport are excluded."}</p>
        }}
    </div>;
}

"""Review, refresh and acceptance for one proposed visit. The checkboxes are the
user's own confirmation and reset whenever the quote revision changes."""
def:pub AcceptPanel(plan: dict, busy: bool, operate: any) -> JsxElement {
    has acknowledged: dict = {}, delivery_ack: dict = {};
    revision = plan["key"] + plan.get("quote_revision", "");
    changes = plan.get("quote_changes", []);
    proposed = plan["status"] == "PROPOSED";
    needs_review = plan["status"] == "NEEDS_REVIEW" or plan.get("quotes_expired", False) or len(changes) > 0;
    ready = acknowledged.get(revision, False) and (not plan.get("delivery_quote", None) or delivery_ack.get(revision, False));
    return <section className="accept-panel" aria-label="Accept this plan">
        {if needs_review {
            <div className="review-box" role="status">
                <h4>{"The price check found changes" if len(changes) > 0 else "This plan needs a fresh check"}</h4>
                <ul>
                    {[<li key={change}>{change}</li> for change in changes]}
                    {if plan.get("quotes_expired", False) { <li>These quote snapshots expired. Refresh before relying on them.</li> }}
                    {if plan.get("review_reason", None) { <li>{plan["review_reason"]}</li> }}
                </ul>
                {if current_kind(plan) and not plan.get("accepted_at", None) {
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "refresh"}); }}>Refresh prices and availability</button>
                }}
            </div>
        }}
        {[<p role="alert" key={blocker}>{blocker}</p> for blocker in plan.get("blockers", [])]}
        {if proposed and plan["accept_allowed"] {
            <div>
                <h3>Before you accept</h3>
                <div className="checks">
                    <label className="check-card"><input type="checkbox" aria-label={"Acknowledge unknown prices and stock at " + plan["store"]["name"]} checked={acknowledged.get(revision, False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(acknowledged)); next_values[revision] = e.target.checked; acknowledged = next_values; }} /><span>I reviewed the product matches and unknowns<small>I will check prices, stock and opening hours before buying.</small></span><span></span></label>
                    {if plan.get("delivery_quote", None) {
                        <label className="check-card"><input type="checkbox" aria-label="Reconfirm delivery checkout" checked={delivery_ack.get(revision, False)} onChange={lambda e: ChangeEvent { next_values = JSON.parse(JSON.stringify(delivery_ack)); next_values[revision] = e.target.checked; delivery_ack = next_values; }} /><span>I rechecked merchant checkout<small>This exact basket, address, all charges and delivery window still apply. I will place the order myself.</small></span><span className="time-chip">{"quote expires " + clock(plan["delivery_quote"]["valid_until"])}</span></label>
                    }}
                </div>
                {if plan.get("delivery_quote", None) {
                    <div className="delivery-box"><b>{"Delivery window " + clock(plan["delivery_quote"]["window_start"]) + "–" + clock(plan["delivery_quote"]["window_end"])}</b><span>Already checked against your free time. The slot is not reserved until you order.</span></div>
                }}
                <div className="info-box"><b>Accepting rechecks each store's price and stock.</b> If nothing changed, the plan is saved. It does not place any delivery order.</div>
                <div className="cta-row">
                    <span>{"Ready to accept" if ready else ("Tick both boxes to continue" if plan.get("delivery_quote", None) else "Tick the box to continue")}</span>
                    <button className="go cta" disabled={busy or not ready} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "accept", "acknowledge_unknowns": True, "quote_revision": plan.get("quote_revision", ""), "delivery_reconfirmed": delivery_ack.get(revision, False)}); }}>Recheck and accept</button>
                </div>
            </div>
        }}
        {if current_kind(plan) and not plan.get("accepted_at", None) and not needs_review {
            <button className="ghost" disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "refresh"}); }}>Refresh prices and availability</button>
        }}
        {if plan["status"] != "COMPLETED" {
            <button className="ghost" disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "cancel"}); }}>Cancel this plan</button>
        }}
    </section>;
}

def:pub VisitHistory(workspace: dict) -> JsxElement {
    if len(workspace.get("visit_history", [])) == 0 { return <span></span>; }
    return <details>
        <summary>Previous visits and purchases</summary>
        {[<article key={old["key"]}>
            <h4>{old["store"]["name"] + " · " + old["status"]}</h4>
            <p>{old["created_at"]}</p>
            {[<p key={item["category"]}>{item["category"] + " · " + item["outcome"] + " · Bought: " + str(item.get("bought_qty", "not recorded")) + " · Paid: " + ("not recorded" if item.get("actual_paid", None) is None else "USD " + str(item["actual_paid"]))}</p> for item in old["items"]]}
        </article> for old in workspace.get("visit_history", [])]}
    </details>;
}
