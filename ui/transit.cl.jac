"""Scheduled bus directions, with separate walking, waiting and ride legs."""
def:pub TransitItinerary(route: dict) -> JsxElement {
    return <section className="transit-itinerary" aria-label="Scheduled bus itinerary">
        <div className="source-note"><strong>THE RIDE · SCHEDULED SERVICE</strong>Published timetable, not a live arrival prediction. Check current service alerts before leaving. Fares are unknown.</div>
        <div className="plan-metrics"><div><small>Total walking</small><strong>{str(route["total_walk_min"]) + " min"}</strong></div><div><small>Waiting, including return</small><strong>{str(route["wait_min"]) + " min"}</strong></div><div><small>Longest walking leg</small><strong>{str(route["walk_min"]) + " min"}</strong></div></div>
        {if route["store_wait_min"] > 0 { <p>{"After 20 minutes shopping, allow " + str(route["store_wait_min"]) + " minutes before starting your return walk. Waiting may be outside the store."}</p> }}
        {[<details key={direction["key"]} open>
            <summary>{direction["label"] + " · " + str(route[direction["key"]]["minutes"]) + " min · " + str(route[direction["key"]]["transfers"]) + " transfers"}</summary>
            <ol className="transit-legs">{[<li key={str(idx)}>
                <span className="transit-kind">{leg["kind"]}</span>
                <div><strong>{("Bus " + leg["route"] + " toward " + leg["headsign"]) if leg["kind"] == "BUS" else ("Walk to " + leg["to"] if leg["kind"] == "WALK" else "Wait at " + leg["from"])}</strong>
                    <p>{leg["departure_at"].slice(0,16).replace("T", " ") + " → " + leg["arrival_at"].slice(0,16).replace("T", " ") + " · " + str(leg["minutes"]) + " min"}</p>
                    {if leg["kind"] == "BUS" { <p>{leg["from"] + " (stop " + leg["from_stop_code"] + ") → " + leg["to"] + " (stop " + leg["to_stop_code"] + ")"}</p> }}
                    <small>{leg["source"]}</small>
                </div>
            </li> for (idx,leg) in enumerate(route[direction["key"]]["legs"])]}</ol>
        </details> for direction in [{"key":"outbound","label":"To the store"},{"key":"returning","label":"Back to your starting address"}]]}
        <small>{"Times in " + route["timezone"] + ". TheRide feed " + route["feed"]["version"] + " · Service dates " + route["feed"]["start_date"] + "–" + route["feed"]["end_date"] + " · Downloaded " + route["feed"]["fetched_at"]}</small>
        <p><a href={route["feed"]["source_url"]} target="_blank" rel="noreferrer">Official timetable source & terms</a> · <a href="https://www.theride.org/rider-alerts" target="_blank" rel="noreferrer">Check TheRide service alerts</a></p>
    </section>;
}
