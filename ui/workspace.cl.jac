"""Profile, location, live catalog and comparable plan controls."""

import from .history { HistoricalPrices }
import from .visits { VisitPlans }
import from .delivery { DeliveryQuotes }

def:pub WorkspacePanel(workspace: dict, mode: str, busy: bool, operate: any, category: str, view: str = "plans") -> JsxElement {
    has address: str = "",
        locating: bool = False, location_notice: str = "",
        max_walk: str = str(workspace["profile"]["max_walk_min"]),
        max_transfers: str = str(workspace["profile"].get("max_transfers", 1)),
        budget: str = str(workspace["profile"]["budget"]),
        carry: str = str(workspace["profile"]["carry_limit_kg"]),
        transport: str = workspace["profile"]["transport"].join(","),
        windows: str = workspace["profile"]["free_windows"].join(";"),
        tax: str = "" if workspace["profile"]["tax_rate"] < 0 else str(workspace["profile"]["tax_rate"]),
        travel: str = "" if workspace["profile"]["transport_cost"] < 0 else str(workspace["profile"]["transport_cost"]),
        dietary: str = workspace["profile"]["dietary"].join(","),
        memberships: str = workspace["profile"]["memberships"].join(","),
        store: str = "",
        weights: dict = {};

    can with (workspace["historical_prices"].get("store_key"), workspace["historical_prices"].get("page")) entry {
        el = document.getElementById("historical-price-results");
        if el { el.scrollIntoView({"block": "start", "behavior": "smooth"}); }
    }

    def locate() -> None {
        if not navigator.geolocation { location_notice = "Location is unavailable. Type your address instead."; return; }
        locating = True;
        location_notice = "Waiting for location permission...";
        navigator.geolocation.getCurrentPosition(
            lambda position: any {
                locating = False; location_notice = "Review and confirm the detected address.";
                operate("device_location", {"lat": position.coords.latitude, "lon": position.coords.longitude, "accuracy_m": position.coords.accuracy});
            },
            lambda error: any { locating = False; location_notice = "Location permission was denied or the request timed out. You can type your address instead."; },
            {"enableHighAccuracy": False, "timeout": 15000, "maximumAge": 60000}
        );
    }

    async def save_profile(e: FormEvent) -> None {
        e.preventDefault();
        values = {"weekly_budget": budget, "carry_limit_kg": carry, "max_walk_min": max_walk,
            "max_transfers": max_transfers,
            "transport": [v.strip().upper() for v in transport.split(",") if v.strip()],
            "free_windows": [v.strip() for v in windows.split(";") if v.strip()],
            "dietary": [v.strip() for v in dietary.split(",") if v.strip()],
            "memberships": [v.strip() for v in memberships.split(",") if v.strip()]};
        if tax != "" { values["tax_rate"] = tax; }
        if travel != "" { values["transport_cost"] = travel; }
        await operate("update_profile", values);
    }

    return <section className="workspace-panel">
        {if workspace["pending_id"] != "" {
            <div className="pending-request">
                <h3>Confirm chat request</h3>
                <pre>{JSON.stringify(workspace["pending_intent"], None, 2)}</pre>
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("confirm_chat", {"id": workspace["pending_id"]}); }}>Confirm changes</button>
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("discard_chat", {}); }}>Discard</button>
            </div>
        }}
        {if view == "profile" {
        <section><h3>Your shopping profile</h3><p>Scheduled TheRide searches support up to two transfers per travel segment and respect lower saved limits.</p><p>Tell the assistant your preferences, or adjust them here. Saved preferences carry over to your next trip.</p>
            <p>{"Saved address: " + (workspace["profile"]["address"] or "Not set")}</p>
            <form onSubmit={save_profile} className="profile-grid">
                <label>Budget ($)<input aria-label="Budget" type="number" min="0" value={budget} onChange={lambda e: ChangeEvent { budget = e.target.value; }} /></label>
                <label>Carrying limit (kg)<input aria-label="Carrying limit" type="number" min="0.1" step="0.1" value={carry} onChange={lambda e: ChangeEvent { carry = e.target.value; }} /></label>
                <label>Maximum walking segment (minutes)<input aria-label="Maximum walking minutes" type="number" min="0" max="240" value={max_walk} onChange={lambda e: ChangeEvent { max_walk = e.target.value; }} /></label>
                <label>Maximum bus transfers per travel segment<input aria-label="Maximum bus transfers" type="number" min="0" max="10" step="1" value={max_transfers} onChange={lambda e: ChangeEvent { max_transfers = e.target.value; }} /></label>
                <label>Transport (comma separated)<input aria-label="Transport" value={transport} placeholder="WALK,BUS" onChange={lambda e: ChangeEvent { transport = e.target.value; }} /></label>
                <label>Free time (semicolon separated)<input aria-label="Free time" value={windows} placeholder="SAT 14:00-17:00;SUN 10:00-12:00" onChange={lambda e: ChangeEvent { windows = e.target.value; }} /></label>
                <label>Estimated tax rate (e.g. 0.06)<input aria-label="Tax rate" type="number" min="0" max="0.3" step="0.001" value={tax} onChange={lambda e: ChangeEvent { tax = e.target.value; }} /></label>
                <label>Estimated round-trip transport ($)<input aria-label="Transport cost" type="number" min="0" step="0.01" value={travel} onChange={lambda e: ChangeEvent { travel = e.target.value; }} /></label>
                <label>Dietary tags (comma separated)<input aria-label="Dietary tags" value={dietary} onChange={lambda e: ChangeEvent { dietary = e.target.value; }} /></label>
                <label>Memberships (comma separated)<input aria-label="Memberships" value={memberships} onChange={lambda e: ChangeEvent { memberships = e.target.value; }} /></label>
                <button type="submit" disabled={busy}>Save profile</button>
            </form>
        </section>
        }}
        {if view == "plans" {
        <div>
        {if mode == "live" {
            <details><summary>Address & nearby supermarkets</summary>
                <button disabled={busy or locating} onClick={lambda e: MouseEvent { locate(); }}>Use my current location</button>
                <p role="status">{location_notice}</p>
                <label>Address<input aria-label="Shopping address" value={address} placeholder="Address, city, ZIP code" onChange={lambda e: ChangeEvent { address = e.target.value; }} /></label>
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("geocode", {"address": address}); }}>Look up address</button>
                {[<div key={a["id"]} className="result-card"><span>{a["address"] + " · " + a["precision"] + (" · accuracy about " + str(a["accuracy_m"]) + " m" if a.get("accuracy_m") else "")}</span><button disabled={busy} onClick={lambda e: MouseEvent { operate("confirm_address", {"id": a["id"]}); }}>Use this address</button></div> for a in workspace["address_candidates"]]}
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("nearby", {}); }}>Find nearby supermarkets</button>
                {[<div key={s["id"]} className="result-card"><strong>{s["name"]}</strong><div>{s["address"]}</div><span>{"Historical price records" if s.get("source") == "openprices" else ("Current product query supported" if s["product_access"] else "Location only — product data unavailable")}</span>
                    {if s.get("source") == "openprices" { <button disabled={busy} onClick={lambda e: MouseEvent { operate("historical_prices", {"store": s["id"]}); }}>View historical products</button> }}
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("store_route", {"store": s["id"], "transport": "WALK"}); }}>Estimate walk</button>
                </div> for s in workspace["stores"]]}
                {if workspace["historical_prices"].get("store_key") { <HistoricalPrices data={workspace["historical_prices"]} busy={busy} operate={operate} /> }}
                <details><summary>Optional Kroger current-price query</summary><label>Product search store<select aria-label="Product search store" value={store} onChange={lambda e: ChangeEvent { store = e.target.value; }}><option value="">Choose a supported store</option>{[<option key={s["id"]} value={s["id"]}>{s["name"] + " · " + s["address"]}</option> for s in workspace["stores"] if s["product_access"] and s.get("source") == "kroger"]}</select></label>
                <button disabled={busy} onClick={lambda e: MouseEvent { operate("search_products", {"store": store, "category": category}); }}>{"Search saved need: " + category}</button>
                {[<div key={prod["result_id"]} className="result-card">
                    <strong>{prod["name"] + " · " + prod["size_label"]}</strong>
                    <p>{(prod["price_label"] + " · " + prod["unit_price_label"]) + " · Inventory: " + prod["availability"]}</p>
                    <small>{"Source: Kroger · Observed: " + prod["observed_at"]}</small><p>{prod.get("match_reason", "Confirm this product before planning.")}</p>
                    <label>Estimated package weight (kg)<input type="number" min="0.001" step="0.001" value={weights.get(prod["result_id"], "")} placeholder={"Enter weight" if prod["weight_kg"] is None else str(prod["weight_kg"])} onChange={lambda e: ChangeEvent { updated = dict(weights); updated[prod["result_id"]] = e.target.value; weights = updated; }} /></label>
                    <button disabled={busy} onClick={lambda e: MouseEvent { operate("confirm_product", {"id": prod["result_id"], "weight_kg": weights.get(prod["result_id"], "")}); }}>Confirm product match</button>
                </div> for prod in workspace["products"]]}</details>
                <p><a href="https://www.geoapify.com/" target="_blank" rel="noreferrer">Powered by Geoapify</a> · © OpenStreetMap contributors. Historical product prices: Open Prices / Open Food Facts (ODbL). Optional current product data: Kroger.</p>
            </details>
        }}
        {[<p role="status" key={str(i)}>{note}</p> for (i, note) in enumerate(workspace["notices"])]}
        {if mode == "mock" {
            <details><summary>{"Compare package and unit prices: " + category}</summary>
                <p>USD; US gallons and fluid ounces. Compare compatible units and product types. Taxes, fees and travel are included separately in plan totals.</p>
                {[<div className="result-card" key={quote["key"]}>
                    <strong>{quote["name"] + " · " + quote["store"]}</strong>
                    <p>{quote["price_label"] + " · " + quote["unit_price_label"]}</p>
                    <p>{quote["channel"] + " · Simulated stock: " + quote["availability"]}</p>
                    {if quote["member_price_applied"] { <p>Eligible membership price applied.</p> }}
                    <small>{"Simulated observation: " + quote["observed_at"] + " · Valid until: " + quote["valid_until"]}</small>
                </div> for quote in workspace["catalog_prices"] if quote["category"] == category]}
            </details>
        }}
        {if mode == "live" { <DeliveryQuotes workspace={workspace} busy={busy} operate={operate} />
            <VisitPlans workspace={workspace} busy={busy} operate={operate} /> }}
        {if mode == "mock" or len(workspace["plans"]) > 0 { <h3>{"Demo shopping plans" if mode == "mock" else "Verified current-price plans"}</h3> }}
        {if mode == "mock" { <button disabled={busy} onClick={lambda e: MouseEvent { operate("plan", {}); }}>Compare plans</button> }}
        {if len(workspace["plans"]) == 0 and mode == "mock" { <p>Save your needs, transport and free time, then compare plans.</p> }}
        {[<article className="result-card" key={plan["key"]}>
            <h4>{plan["strategy"] + " · " + plan["status"]}</h4>
            <p>{"Estimated $" + str(plan["total"]) + " · " + str(plan["minutes"]) + " active minutes · " + str(plan["weight"]) + " kg"}</p>
            <p style={{"whiteSpace": "pre-wrap"}}>{plan["explanation"]}</p>
            {if plan["status"] == "PROPOSED" { <button disabled={busy} onClick={lambda e: MouseEvent { operate("plan_action", {"key": plan["key"], "action": "accept"}); }}>Accept plan</button> }}
            {if plan["status"] not in ["COMPLETED", "CANCELLED"] { <button disabled={busy} onClick={lambda e: MouseEvent { operate("plan_action", {"key": plan["key"], "action": "cancel"}); }}>Cancel plan</button> }}
            {[<div key={item["name"]}><span>{str(item["qty"]) + " × " + item["name"] + " · " + item["outcome"]}</span><p>{item["price_label"] + " · " + item["unit_price_label"] + " (at planning time)"}</p>
                {if plan["status"] in ["ACCEPTED", "IN_PROGRESS"] and item["outcome"] == "PENDING" {
                    <span><button disabled={busy} onClick={lambda e: MouseEvent { operate("feedback", {"id": crypto.randomUUID(), "type": "feedback", "target": item["name"], "reason": "PURCHASED"}); }}>Bought item</button><button disabled={busy} onClick={lambda e: MouseEvent { operate("feedback", {"id": crypto.randomUUID(), "type": "feedback", "target": item["name"], "reason": "OUT_OF_STOCK"}); }}>Out of stock</button></span>
                }}
            </div> for item in plan["items"]]}
        </article> for plan in workspace["plans"]]}
        </div>
        }}
    </section>;
}
