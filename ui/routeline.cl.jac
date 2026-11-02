"""Route stage: the trip drawn as one line in time order, the moments that matter,
and what the shopper carries home. Scheduled data only; nothing moves like a live bus."""
import from .planview { trip_segments, key_times, carried, weight_tally, tally_label, delivered_items, facts, kg, money, duration, clock }
import from .options { Metrics, CostBreakdown }
import from .visits { AcceptPanel }
import from .transit { TransitItinerary }
import from .itinerary { StoreItinerary }

def:pub RouteLine(plan: dict) -> JsxElement {
    segments = trip_segments(plan);
    if len(segments) == 0 { return <span></span>; }
    total = 0;
    for seg in segments { total += seg["min"]; }
    colors = {"WALK": "#b3bdb5", "BIKE": "#b3bdb5", "WAIT": "#d3d9d1", "BUS": "#2a6fcf", "CAR": "#7d8ca0", "SHOP": "#2f8a5a", "ORDER": "#e0a440"};
    widths = {"WALK": 4, "BIKE": 4, "WAIT": 3, "BUS": 8, "CAR": 6, "SHOP": 10, "ORDER": 4};
    width = 660; left = 30; y = 34;
    pieces = [];
    x = left; delay = 0;
    for seg in segments {
        span = Math.max(6, seg["min"] / total * width);
        pieces.append({"x0": x, "x1": x + span, "kind": seg["kind"], "label": seg["label"], "min": seg["min"], "delay": delay});
        x += span; delay += 180;
    }
    end = x;
    return <div className="route-map">
        <svg viewBox={"0 0 " + str(end + 30) + " 74"} role="img" aria-label={"Trip in order: " + [p["kind"].lower() + " " + str(Math.round(p["min"])) + " min" for p in pieces].join(", ")}>
            {[<path key={"s" + str(i)} className="route-seg" pathLength="1" d={"M" + str(p["x0"] + 1) + "," + str(y) + " L" + str(p["x1"] - 1) + "," + str(y)} stroke={colors.get(p["kind"], "#b3bdb5")} strokeWidth={widths.get(p["kind"], 4)} style={{"animationDelay": str(p["delay"]) + "ms"}} /> for (i, p) in enumerate(pieces)]}
            {[<g key={"b" + str(i)} className="route-node" style={{"animationDelay": str(p["delay"] + 200) + "ms"}}><rect x={(p["x0"] + p["x1"]) / 2 - 16} y={y - 25} width="32" height="17" rx="5" fill="#2a6fcf" /><text x={(p["x0"] + p["x1"]) / 2} y={y - 12.5} textAnchor="middle" fontSize="11" fontWeight="800" fill="#fff">{p["label"] or "Bus"}</text></g> for (i, p) in enumerate(pieces) if p["kind"] == "BUS"]}
            {[<g key={"h" + str(i)} className="route-node" style={{"animationDelay": str(p["delay"] + 200) + "ms"}}><circle cx={(p["x0"] + p["x1"]) / 2} cy={y} r="9" fill="#2f8a5a" stroke="#17251d" strokeWidth="3" /><text x={(p["x0"] + p["x1"]) / 2} y={y + 25} textAnchor="middle" fontSize="11" fontWeight="700" fill="#17251d">{p["label"] if len(p["label"]) <= 22 else p["label"].slice(0, 21) + "…"}</text></g> for (i, p) in enumerate(pieces) if p["kind"] == "SHOP"]}
            <circle cx={left} cy={y} r="8" fill="#7af0b4" stroke="#17251d" strokeWidth="3" />
            <text x={left} y={y + 25} textAnchor="middle" fontSize="11" fontWeight="700" fill="#17251d">Home</text>
            <circle cx={end} cy={y} r="8" fill="#7af0b4" stroke="#17251d" strokeWidth="3" className="route-node" style={{"animationDelay": str(delay) + "ms"}} />
            <text x={end} y={y + 25} textAnchor="middle" fontSize="11" fontWeight="700" fill="#17251d">Home</text>
        </svg>
        <div className="route-legend"><span><i style={{"background": "#b3bdb5"}}></i>Walk</span><span><i style={{"background": "#d3d9d1"}}></i>Wait</span><span><i style={{"background": "#2a6fcf"}}></i>Bus</span><span><i style={{"background": "#2f8a5a"}}></i>Shop</span>{if plan.get("delivery_quote", None) { <span><i style={{"background": "#e0a440"}}></i>Place delivery order</span> }}</div>
    </div>;
}

"""Key times; after a change, each moment shows its previous value struck through."""
def:pub KeyTimes(route: any) -> JsxElement {
    has seen: str = "", previous: list = [];
    times = key_times(route);
    signature = [t["label"] + "=" + t["value"] for t in times].join("|");
    can with (signature) entry {
        if seen != "" and seen != signature { previous = seen.split("|"); }
        seen = signature;
    }
    if len(times) == 0 { return <span></span>; }
    def before(label: str, value: str) -> str {
        for prior in previous {
            parts = prior.split("=");
            if parts[0] == label and parts[1] != value { return parts[1]; }
        }
        return "";
    }
    return <div className="key-times">{[<div key={t["label"] + t["value"]} className="key-time" id={"chg-leave" if i == 0 else ""}><small>{t["label"]}</small><b className={"hl" if before(t["label"], t["value"]) else ""}>{t["value"]}</b>{if before(t["label"], t["value"]) { <s>{before(t["label"], t["value"])}</s> }}</div> for (i, t) in enumerate(times)]}</div>;
}

def:pub CarryCheck(plan: dict, limit: any) -> JsxElement {
    rows = carried(plan);
    weight = weight_tally(plan);
    known = weight["total"]; unknown = weight["missing"];
    scale = Math.max(limit or 1, known);
    over = limit is not None and known > limit;
    palette = ["#4f8fd8", "#9a8455", "#d89a3f", "#3f8f63", "#8a6fc0", "#c76b5a"];
    delivered = delivered_items(plan);
    return <div className="side-box">
        <h4>Carry check</h4>
        <div className="carry-big"><b>{tally_label(weight, kg)}</b><span>{"of " + kg(limit)}</span></div>
        <div className={"carry-bar" + (" over" if over else "")} aria-hidden="true">
            {[<i key={row["name"]} style={{"flex": str(row["kg"]), "background": palette[i % len(palette)], "animationDelay": str(300 + i * 160) + "ms"}}>{row["name"] if row["kg"] >= scale * 0.18 else ""}</i> for (i, row) in enumerate(rows) if row["kg"] is not None]}
            {if scale - known > 0 { <i style={{"flex": str(scale - known), "background": "transparent"}}></i> }}
        </div>
        {if over { <p role="alert">{"Over your carrying limit by " + kg(known - limit) + "."}</p> }}
        {if unknown > 0 { <p>{("Weight unknown for every item" if weight["known"] == 0 else str(unknown) + (" item has" if unknown == 1 else " items have") + " no known weight") + ". Check it fits your bags before you go; packaging is not included."}</p> }}
        {if len(delivered) > 0 and plan.get("delivery_quote", None) {
            <div className="delivery-box"><b>{"Delivered: " + [item["category"] for item in delivered].join(", ")}</b><span>{"Window " + clock(plan["delivery_quote"]["window_start"]) + "–" + clock(plan["delivery_quote"]["window_end"]) + ". You don't carry these."}</span></div>
        }}
    </div>;
}

def:pub RouteStage(plan: any, workspace: dict, busy: bool, operate: any, find: any) -> JsxElement {
    if not plan {
        return <div className="empty-list"><h3>No open shopping option</h3><p>Options are cleared whenever your list, address or preferences change, so prices and routes are never out of date. Compare stores again to choose a route and accept it.</p><button className="primary" disabled={busy} onClick={lambda e: MouseEvent { find(); }}>{"Comparing stores…" if busy else "Find shopping options"}</button></div>;
    }
    row = facts(plan);
    limit = workspace["profile"]["carry_limit_kg"];
    route = plan.get("route", None);
    return <div>
        <div className="stage-head"><h3>{row["title"]}</h3><small>{"TheRide published timetable, not live arrivals" if route and route.get("mode", None) == "BUS" else ("Scheduled estimate" if route else "")}</small></div>
        {if route or plan.get("delivery_quote", None) { <RouteLine plan={plan} /> }}
        <KeyTimes route={route} />
        <div className="route-grid">
            <div>
                <Metrics row={row} carry_limit={limit} />
                <div className="info-box">
                    {if route and route.get("outbound", None) {
                        <span>{"Walking " + str(route.get("total_walk_min", 0)) + " min · waiting " + str(route.get("wait_min", 0)) + " min · shopping 20 min" + (" · plus 10 min to place the delivery order" if plan.get("delivery_quote", None) else "")}</span>
                    } elif route { <span>{"Round trip " + duration(route.get("total_min", None) or route.get("min", None)) + " including shopping"}</span> } else { <span>No store trip. Delivery only.</span> }}
                </div>
                <CostBreakdown plan={plan} profile={workspace["profile"]} />
                {if route and route.get("segments", None) { <details><summary>Show all steps</summary><StoreItinerary route={route} /></details> } elif route and route.get("scheduled_only", None) { <details><summary>Show all steps</summary><TransitItinerary route={route} /></details> }}
                {if route and plan.get("navigation_url", None) { <p><a href={plan["navigation_url"]} target="_blank" rel="noreferrer">Directions from your confirmed address ↗</a></p> }}
            </div>
            <CarryCheck plan={plan} limit={limit} />
        </div>
        <AcceptPanel plan={plan} busy={busy} operate={operate} />
    </div>;
}
