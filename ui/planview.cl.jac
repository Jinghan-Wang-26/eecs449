"""Plan facts shared by the Options, Route and Shop stages.

Store-visit plans come in several kinds; `facts` gives them all the same few
fields. Unknown values stay None and render as "Unknown".
"""

def:pub money(value: any) -> str {
    if value is None { return "Unknown"; }
    return "$" + Number(value).toFixed(2);
}

def:pub duration(minutes: any) -> str {
    if minutes is None or minutes >= 100000 { return "Unknown"; }
    m = Math.round(minutes);
    if m < 60 { return str(m) + " min"; }
    return str(Math.floor(m / 60)) + " h " + str(m % 60) + " min";
}

def:pub kg(value: any) -> str {
    if value is None { return "Unknown"; }
    return str(Math.round(value * 10) / 10) + " kg";
}

def:pub clock(iso: any, tz: str = "") -> str {
    if not iso { return "—"; }
    try {
        date = window.Reflect.construct(window.Date, [iso]);
        opts = {"hour": "numeric", "minute": "2-digit"};
        if tz { opts["timeZone"] = tz; }
        return date.toLocaleTimeString("en-US", opts);
    } except Exception {
        return str(iso).slice(11, 16);
    }
}

def:pub current_kind(plan: dict) -> bool {
    return plan.get("kind", None) in ["CURRENT_STORE_VISIT", "CURRENT_MULTI_VISIT", "DELIVERY_VISIT", "MIXED_VISIT"];
}

def:pub delivered_items(plan: dict) -> list {
    return [item for item in plan.get("items", []) if item.get("fulfillment", None) == "DELIVERY"];
}

def:pub store_names(plan: dict) -> list {
    if plan.get("stops", None) { return [stop["name"] for stop in plan["stops"]]; }
    if plan.get("store", None) and plan.get("kind", None) != "DELIVERY_VISIT" { return [plan["store"]["name"]]; }
    return [];
}

def:pub plan_title(plan: dict) -> str {
    if plan.get("kind", None) == "DELIVERY_VISIT" {
        return "Delivery only · " + (plan.get("delivery_quote", None) or {}).get("merchant", "merchant");
    }
    title = store_names(plan).join(" + ");
    delivered = [item["category"] for item in delivered_items(plan)];
    if len(delivered) > 0 { title += " + delivered " + delivered.join(", "); }
    return title or "Store visit";
}

def:pub plan_minutes(plan: dict) -> any {
    if plan.get("active_min", None) is not None and plan["active_min"] < 100000 { return plan["active_min"]; }
    route = plan.get("route", None);
    if route {
        if route.get("total_min", None) is not None { return route["total_min"]; }
        if route.get("min", None) is not None { return route["min"] + 20; }
    }
    return None;
}

def:pub plan_total(plan: dict) -> any {
    if current_kind(plan) { return plan.get("estimated_total", None); }
    return None;
}

"""Known store-item subtotal plus estimated tax, shown when the full total is unknown (usually bus fare)."""
def:pub plan_items_total(plan: dict) -> any {
    if not current_kind(plan) { return None; }
    base = plan["retail_subtotal"] if plan.get("retail_subtotal", None) is not None else plan.get("current_subtotal", None);
    if base is None or plan.get("tax_estimate", None) is None { return base; }
    return Math.round((base + plan["tax_estimate"]) * 100) / 100;
}

"""A sum that remembers what it could not count: {"total", "known", "missing"}."""
def:pub tally(values: list) -> dict {
    out = {"total": 0, "known": 0, "missing": 0};
    for value in values {
        if value is None { out["missing"] += 1; } else { out["total"] += value; out["known"] += 1; }
    }
    return out;
}

"""Unknown when nothing is known, "≥ x" when some values are missing."""
def:pub tally_label(t: dict, fmt: any) -> str {
    if t["missing"] > 0 and t["known"] == 0 { return "Unknown"; }
    return ("≥ " if t["missing"] > 0 else "") + fmt(t["total"]);
}

"""Weight the shopper carries home. The server's known net weight is preferred over our sum."""
def:pub weight_tally(plan: dict) -> dict {
    t = tally([row["kg"] for row in carried(plan)]);
    if t["known"] > 0 and plan.get("known_net_weight_kg", None) is not None { t["total"] = plan["known_net_weight_kg"]; }
    return t;
}

def:pub plan_weight(plan: dict) -> any {
    t = weight_tally(plan);
    return None if t["known"] == 0 and t["missing"] > 0 else t["total"];
}

def:pub facts(plan: dict) -> dict {
    eligible = plan.get("accept_allowed", False) and plan["status"] == "PROPOSED";
    return {"key": plan["key"], "title": plan_title(plan), "total": plan_total(plan), "minutes": plan_minutes(plan),
        "weight": plan_weight(plan), "weight_missing": weight_tally(plan)["missing"], "items": plan_items_total(plan), "items_taxed": plan.get("tax_estimate", None) is not None, "labels": plan.get("comparison_labels", []), "eligible": eligible, "status": plan["status"],
        "blockers": plan.get("blockers", []), "plan": plan};
}

"""Pick the plan to recommend: the server's Balanced label first, then server order."""
def:pub recommended(rows: list) -> any {
    eligible = [row for row in rows if row["eligible"]];
    for row in eligible {
        if "Balanced" in row["labels"] { return row; }
    }
    return eligible[0] if len(eligible) > 0 else None;
}

"""One sentence from known numbers only, e.g. "Costs $0.53 more than X, but takes 17 min less."."""
def:pub reason_sentence(best: dict, rows: list, blocked_count: int) -> str {
    others = [row for row in rows if row["eligible"] and row["key"] != best["key"] and row["total"] is not None and row["minutes"] is not None];
    if best["total"] is None or best["minutes"] is None {
        return "";
    }
    if len(others) == 0 {
        return "The only option that fits your limits." if blocked_count > 0 else "";
    }
    cheaper = [row for row in others if row["total"] < best["total"]];
    faster = [row for row in others if row["minutes"] < best["minutes"]];
    if len(cheaper) > 0 {
        cheapest = cheaper[0];
        for row in cheaper { if row["total"] < cheapest["total"] { cheapest = row; } }
        saved = Math.round(cheapest["minutes"] - best["minutes"]);
        if saved > 0 {
            return "Costs " + money(best["total"] - cheapest["total"]) + " more than " + cheapest["title"] + ", but takes " + str(saved) + " min less.";
        }
        return "";
    }
    if len(faster) > 0 {
        fastest = faster[0];
        for row in faster { if row["minutes"] < fastest["minutes"] { fastest = row; } }
        return "Saves " + money(fastest["total"] - best["total"]) + " compared with " + fastest["title"] + ", which takes " + str(Math.round(best["minutes"] - fastest["minutes"])) + " min less.";
    }
    return "Lowest estimated total and least active time of the options that fit your limits.";
}

"""Time-strip segments in trip order: legs, shopping time, and the delivery-order allowance."""
def:pub trip_segments(plan: dict) -> list {
    out = [];
    route = plan.get("route", None);
    if route {
        if route.get("outbound", None) and route.get("returning", None) {
            for leg in route["outbound"].get("legs", []) { out.append({"kind": leg["kind"], "min": leg["minutes"], "label": leg.get("route", "")}); }
            out.append({"kind": "SHOP", "min": route.get("shop_min", 20), "label": store_names(plan).join(" + ")});
            for leg in route["returning"].get("legs", []) { out.append({"kind": leg["kind"], "min": leg["minutes"], "label": leg.get("route", "")}); }
        } elif route.get("segments", None) {
            stops = route.get("stops", []);
            for (idx, segment) in enumerate(route["segments"]) {
                legs = segment.get("legs", []);
                if len(legs) > 0 {
                    for leg in legs { out.append({"kind": leg["kind"], "min": leg["minutes"], "label": leg.get("route", "")}); }
                } else {
                    out.append({"kind": route.get("mode", "WALK"), "min": segment["minutes"], "label": ""});
                }
                if idx < len(stops) {
                    out.append({"kind": "SHOP", "min": 20, "label": stops[idx]["name"]});
                }
            }
        } elif route.get("min", None) is not None {
            half = route["min"] / 2;
            out.append({"kind": route.get("mode", "WALK"), "min": half, "label": ""});
            out.append({"kind": "SHOP", "min": 20, "label": store_names(plan).join(" + ")});
            out.append({"kind": route.get("mode", "WALK"), "min": half, "label": ""});
        }
    }
    if plan.get("delivery_quote", None) {
        out.append({"kind": "ORDER", "min": 10, "label": "Order delivery"});
    }
    return [seg for seg in out if seg["min"] > 0];
}

def:pub route_zone(route: any) -> str {
    if not route { return ""; }
    return route.get("timezone", None) or route.get("store_timezone", None) or "";
}

"""Five moments a shopper plans around: leave, first bus, store, return bus, home."""
def:pub key_times(route: any) -> list {
    if not route { return []; }
    tz = route_zone(route);
    out = [];
    if route.get("outbound", None) and route.get("returning", None) {
        go = route["outbound"].get("legs", []);
        back = route["returning"].get("legs", []);
        if len(go) > 0 { out.append({"label": "Leave home", "value": clock(go[0]["departure_at"], tz)}); }
        buses = [leg for leg in go if leg["kind"] == "BUS"];
        if len(buses) > 0 { out.append({"label": "Bus " + buses[0].get("route", ""), "value": clock(buses[0]["departure_at"], tz)}); }
        if len(go) > 0 { out.append({"label": "At the store", "value": clock(go[len(go) - 1]["arrival_at"], tz)}); }
        returns = [leg for leg in back if leg["kind"] == "BUS"];
        if len(returns) > 0 { out.append({"label": "Bus " + returns[0].get("route", "") + " back", "value": clock(returns[0]["departure_at"], tz)}); }
        if len(back) > 0 { out.append({"label": "Home", "value": clock(back[len(back) - 1]["arrival_at"], tz)}); }
    } elif route.get("segments", None) {
        segments = route["segments"];
        out.append({"label": "Leave home", "value": clock(segments[0]["departure_at"], tz)});
        for stop in route.get("stops", []) { out.append({"label": stop["name"], "value": clock(stop["shopping_at"], tz)}); }
        out.append({"label": "Home", "value": clock(segments[len(segments) - 1]["arrival_at"], tz)});
    } else {
        if route.get("departure_at", None) { out.append({"label": "Leave home", "value": clock(route["departure_at"], tz)}); }
        if route.get("arrival_at", None) { out.append({"label": "At the store", "value": clock(route["arrival_at"], tz)}); }
        if route.get("leave_store_at", None) { out.append({"label": "Leave the store", "value": clock(route["leave_store_at"], tz)}); }
        if route.get("return_at", None) { out.append({"label": "Home", "value": clock(route["return_at"], tz)}); }
    }
    return out;
}

"""The "Leave home" and "Home" times, or "" when the route does not give them."""
def:pub trip_ends(route: any) -> dict {
    out = {"leave": "", "home": ""};
    for t in key_times(route) {
        if t["label"] == "Leave home" { out["leave"] = t["value"]; }
        if t["label"] == "Home" { out["home"] = t["value"]; }
    }
    return out;
}

"""Items that travel home in the shopper's bags, with known weight or None."""
def:pub carried(plan: dict) -> list {
    out = [];
    for item in plan.get("items", []) {
        if item.get("fulfillment", None) == "DELIVERY" { continue; }
        weight = (item.get("quote", None) or {}).get("weight_kg", None);
        if weight is None { weight = (item.get("evidence", None) or {}).get("weight_kg", None); }
        out.append({"name": item["category"], "kg": None if weight is None else weight * item["qty"], "item": item});
    }
    return out;
}

def:pub item_amount(item: dict) -> any {
    if item.get("current_amount", None) is not None { return item["current_amount"]; }
    return item.get("reference_amount", None);
}

"""Turn "SAT 14:00-17:00" into a day and a time range; anything else stays raw."""
def:pub parse_windows(windows: list) -> list {
    out = [];
    for raw in windows {
        parts = raw.strip().split(" ");
        times = parts[1].split("-") if len(parts) == 2 else [];
        if len(times) == 2 and len(parts[0]) == 3 {
            out.append({"day": parts[0].upper(), "start": times[0], "end": times[1], "raw": ""});
        } else {
            out.append({"day": "", "start": "", "end": "", "raw": raw});
        }
    }
    return out;
}

def:pub window_label(raw: str) -> str {
    rows = parse_windows([raw]);
    row = rows[0];
    if row["raw"] { return row["raw"]; }
    return row["day"].slice(0, 1) + row["day"].slice(1).lower() + " " + row["start"] + "–" + row["end"];
}

def:pub list_names(snapshot: dict) -> list {
    return [item["category"] for item in snapshot.get("interests", []) if item.get("in_current_list", True) and item.get("status", None) != "PAUSED"];
}

def:pub open_plans(snapshot: dict) -> list {
    ws = snapshot.get("workspace", None);
    if not ws { return []; }
    plans = ws["visit_plans"];
    return [plan for plan in plans if plan["status"] in ["PROPOSED", "NEEDS_REVIEW"]];
}

def:pub accepted_plans(snapshot: dict) -> list {
    ws = snapshot.get("workspace", None);
    if not ws { return []; }
    plans = ws["visit_plans"];
    return [plan for plan in plans if plan["status"] in ["ACCEPTED", "IN_PROGRESS"]];
}

"""What a chat reply changed in the workspace, for the change card in the chat."""
def:pub describe_changes(before: dict, after: dict) -> list {
    out = [];
    old_ws = before.get("workspace", None); new_ws = after.get("workspace", None);
    if not old_ws or not new_ws { return out; }
    a = old_ws["profile"]; b = new_ws["profile"];
    if a["budget"] != b["budget"] { out.append({"label": "Weekly budget", "before": money(a["budget"]), "after": money(b["budget"]), "target": "chg-left"}); }
    if a["carry_limit_kg"] != b["carry_limit_kg"] { out.append({"label": "Carry limit", "before": kg(a["carry_limit_kg"]), "after": kg(b["carry_limit_kg"]), "target": "chg-carry-limit"}); }
    if JSON.stringify(a["free_windows"]) != JSON.stringify(b["free_windows"]) {
        out.append({"label": "Free time", "before": [window_label(w) for w in a["free_windows"]].join(", ") or "None", "after": [window_label(w) for w in b["free_windows"]].join(", ") or "None", "target": "chg-free"});
    }
    if JSON.stringify(a["transport"]) != JSON.stringify(b["transport"]) { out.append({"label": "Travel", "before": a["transport"].join(" + ") or "None", "after": b["transport"].join(" + ") or "None", "target": "chg-travel"}); }
    if a["address"] != b["address"] { out.append({"label": "Start address", "before": a["address"] or "Not set", "after": b["address"] or "Not set", "target": "chg-address"}); }
    old_list = list_names(before); new_list = list_names(after);
    added = [name for name in new_list if name not in old_list];
    removed = [name for name in old_list if name not in new_list];
    if len(added) > 0 { out.append({"label": "Added to list", "before": "", "after": added.join(", "), "target": "chg-list"}); }
    if len(removed) > 0 { out.append({"label": "Removed from list", "before": "", "after": removed.join(", "), "target": "chg-list"}); }
    old_open = [facts(p) for p in open_plans(before)]; new_open = [facts(p) for p in open_plans(after)];
    if JSON.stringify([r["key"] for r in old_open]) != JSON.stringify([r["key"] for r in new_open]) {
        out.append({"label": "Shopping options", "before": str(len(old_open)), "after": str(len(new_open)), "target": "chg-plans"});
        old_best = recommended(old_open); new_best = recommended(new_open);
        if old_best and new_best and old_best["total"] != new_best["total"] {
            out.append({"label": "Recommended total", "before": money(old_best["total"]), "after": money(new_best["total"]), "target": "chg-total"});
        }
        if old_best and new_best {
            old_times = key_times(old_best["plan"].get("route", None)); new_times = key_times(new_best["plan"].get("route", None));
            if len(old_times) > 0 and len(new_times) > 0 and old_times[0]["value"] != new_times[0]["value"] {
                out.append({"label": "Leave home", "before": old_times[0]["value"], "after": new_times[0]["value"], "target": "chg-leave"});
            }
        }
    }
    return out;
}

"""Street part of an address. Reverse geocoding can put a place name first
("Panda Express, 530 South State Street, ...")."""
def:pub short_address(address: str) -> str {
    if not address { return ""; }
    parts = [part.strip() for part in address.split(",")];
    if len(parts) > 1 and not ("0" <= parts[0].slice(0, 1) and parts[0].slice(0, 1) <= "9") and "0" <= parts[1].slice(0, 1) and parts[1].slice(0, 1) <= "9" {
        return parts[1];
    }
    return parts[0];
}
