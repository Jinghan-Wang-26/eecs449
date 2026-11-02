"""Grounded follow-up questions and summaries, implemented in Jac."""

def language(text: str, previous: str = "en") -> str {
    # The application always responds in English, including legacy sessions.
    return "en";
}

def missing_fields(context: dict) -> list {
    missing = [];
    if context["data_mode"] == "live" and (context.get("address_pending") or not context["has_confirmed_address"]) { missing.append("address"); }
    if not context["needs"] { missing.append("needs"); }
    modes = context["transport"];
    if not modes or (context["data_mode"] == "live" and not any([m in ["WALK", "BIKE", "CAR", "BUS"] for m in modes])) { missing.append("transport"); }
    if not context.get("free_windows") { missing.append("free_windows"); }
    if context["data_mode"] == "mock" and context["budget"] <= 0 { missing.append("weekly_budget"); }
    return missing;
}

def question(context: dict, field: str, lang: str) -> str {
    if field == "address" {
        candidates = context.get("address_candidates", []) if context.get("address_pending") else [];
        if candidates {
            title = "Which starting address should I use? Reply with its number, or type a different address:";
            return title + "\n" + "\n".join([f"{i+1}. {c['address']}" for (i,c) in enumerate(candidates)]);
        }
        return "Where will you start shopping? Tell me your address, city and ZIP code here.";
    }
    messages = {
        "needs": "What would you like to buy, and how many packages of each? Tell me here, for example two milk and one rice.",
        "transport": "How will you travel: walk, cycle, drive or bus? Scheduled bus trips currently cover TheRide in Ann Arbor/Ypsilanti.",
        "free_windows": "What day and time range are you free to shop? For example, Saturday 2–5 pm. Reply here.",
        "weekly_budget": "What is your shopping budget in dollars?"};
    return str(messages[field]);
}

def saved_message(proposal: dict, lang: str) -> str {
    parts = [];
    for (k,v) in proposal["profile"].items() {
        label = k.replace("_", " ");
        parts.append(f"{label}: {v}");
    }
    for n in proposal["needs"] {
        detail = f"{n['qty']} × {n['type']}" if 'qty' in n else n['type'];
        specs = [f"{k}: {n[k] or '(cleared)'}" for k in ['brand', 'variant', 'size'] if k in n];
        parts.append(detail + (" (" + ", ".join(specs) + ")" if specs else ""));
    }
    if not parts { return ""; }
    prefix = "Updated your shopping information: ";
    return prefix + "; ".join(parts) + ".\n";
}

# Product families where shoppers usually care about brand, flavor or size. Staples such
# as milk, eggs or rice are left alone: the cheapest suitable in-stock package is fine.
glob VARIED_WORDS: list = ["chips", "crisps", "snack", "snacks", "cookie", "cookies", "cracker", "crackers",
    "cereal", "granola", "coffee", "tea", "soda", "pop", "juice", "chocolate", "candy", "ice cream",
    "yogurt", "yoghurt", "noodles", "ramen", "pasta sauce", "salsa", "dressing", "bars", "protein bars",
    "pizza", "beer", "wine", "detergent", "laundry detergent", "shampoo", "conditioner", "toothpaste",
    "body wash", "deodorant", "pet food", "dog food", "cat food"];

"""A newly added need that comes in many brands and flavors and has no preference yet."""
def needs_variety(spec: dict) -> bool {
    if spec.get("brand") or spec.get("variant") or spec.get("size") { return False; }
    name = " " + str(spec.get("type", "")).lower() + " ";
    return any([(" " + word + " ") in name for word in VARIED_WORDS]);
}

"""One question for every such item, with a way to skip it."""
def variety_question(categories: list) -> str {
    names = categories[0] if len(categories) == 1 else ", ".join(categories[:-1]) + " and " + categories[-1];
    examples = {"chips": "Lay's classic, 8 oz", "crisps": "Lay's classic, 8 oz", "coffee": "Starbucks Pike Place, 12 oz", "cereal": "Cheerios original",
        "soda": "Coca-Cola, 12 pack", "yogurt": "Chobani vanilla", "laundry detergent": "Tide unscented", "detergent": "Tide unscented",
        "ice cream": "Ben & Jerry's chocolate", "tea": "Twinings earl grey", "juice": "Tropicana no pulp, 52 oz"};
    known = [examples[c] for c in categories if c in examples];
    hint = (f" For example \"{known[0]}\".") if known else "";
    return f"Any brand, flavor or size you want for {names}?{hint} Or say \"any\" and I'll pick the best-value one that's in stock.";
}

def clock_of(value: any) -> str {
    return str(value)[11:16] if value and len(str(value)) >= 16 else "";
}

"""One short line about getting there and back, from known times only."""
def trip_line(route: any) -> str {
    if not route { return "no store trip"; }
    text = f"{route['mode'].lower()} {route['min']} min round trip + {route['shopping_min']} min shopping";
    if route['mode'] == 'BUS' and not route.get('segments') {
        buses = [];
        for (label, direction) in [('out', route['outbound']), ('back', route['returning'])] {
            for leg in direction['legs'] {
                if leg['kind'] == 'BUS' { buses.append(f"scheduled bus {leg['route']} {label} at {clock_of(leg['departure_at'])}"); }
            }
        }
        text += "; " + ", ".join(buses) + " (timetable only; live delays/cancellations and fares are unknown)";
    }
    leave = clock_of(route.get('departure_at')); home = clock_of(route.get('return_at'));
    if leave { text += f"; leave {leave}" + (f", home {home}" if home else ""); }
    elif not route.get('window') { text += "; no fitting time window"; }
    return text;
}

"""What is known about price and stock, without turning unknown into zero."""
def price_line(p: dict) -> str {
    if p.get('kind') in ['CURRENT_STORE_VISIT','CURRENT_MULTI_VISIT','DELIVERY_VISIT','MIXED_VISIT'] {
        price = f"USD {p['current_subtotal']} items at regular price" if p.get('current_subtotal') is not None else "current price Unknown";
        text = f"{p['current_available']}/{p['need_count']} in stock at last check; {price}";
        if p.get('estimated_total') is not None { text += f"; about USD {p['estimated_total']} in total"; }
        return text;
    }
    price = f"USD {p['reference_subtotal']} historical reference, not today's price" if p["reference_subtotal"] is not None else "price unknown";
    return f"{p['matched']}/{p['need_count']} items matched in historical records; {price}";
}

def option_name(p: dict) -> str {
    if p.get('stops') { return " + ".join([stop['name'] for stop in p['stops']]); }
    if p.get('kind') == 'DELIVERY_VISIT' { return "Delivery from " + (p.get('delivery_quote') or {}).get('merchant', 'merchant'); }
    name = p['store']['name'];
    delivered = [item['category'] for item in p['items'] if item.get('fulfillment') == 'DELIVERY'];
    return name + (" + delivered " + ", ".join(delivered) if delivered else "");
}

"""Lead with the recommendation, give one line per other usable option, and fold the
options that do not fit into their reasons. Full evidence stays in the Options step."""
def plan_summary(workspace: dict, lang: str) -> str {
    plans = [p for p in workspace["visit_plans"] if p["status"] == "PROPOSED"];
    if not plans {
        notices = "\n".join(workspace.get("notices", []));
        if notices { return notices; }
        return "No nearby stores were found. Try a wider radius or another starting address.";
    }
    usable = [p for p in plans if p["accept_allowed"]];
    blocked = [p for p in plans if not p["accept_allowed"]];
    # Same choice as the Options step: the Balanced option first, otherwise the server's order.
    balanced = [p for p in usable if "Balanced" in p.get('comparison_labels', [])];
    best = balanced[0] if balanced else (usable[0] if usable else None);
    lines = [f"Found {len(plans)} store options; {len(usable)} can be reviewed and accepted."];
    if best {
        # A route that fits is not a verified basket; say so when no product evidence exists.
        unverified = best.get('current_available', best.get('matched', 0)) == 0;
        lead = "Fits your time and travel limits (products not confirmed yet)" if unverified else "Recommended";
        lines.append(f"{lead}: {option_name(best)}. {trip_line(best['route'])[0].upper() + trip_line(best['route'])[1:]}. {price_line(best)}.");
        if best.get('delivery_quote') { lines.append("Delivery uses the checkout quote you entered; accepting does not place an order."); }
        # Stores with a fitting route but no product data at all get one shared line.
        bare = [p for p in usable if p is not best and not (p.get('current_available') or p.get('matched'))];
        for p in usable {
            if p is not best and p not in bare { lines.append(f"Also possible: {option_name(p)} ({trip_line(p['route'])}; {price_line(p)})."); }
        }
        if bare { lines.append(f"{len(bare)} more nearby " + ("store fits" if len(bare) == 1 else "stores fit") + " your route but " + ("has" if len(bare) == 1 else "have") + " no price or stock data."); }
    }
    if blocked {
        lines.append(("Not usable yet:" if best else "None of them fit yet:"));
        for p in blocked {
            reasons = [r.rstrip('.') for r in (list(p["blockers"]) + list(p["route_notices"]))[:2]];
            lines.append(f"- {option_name(p)}: " + ("; ".join(reasons) or "does not fit your limits") + f" ({price_line(p)}).");
        }
    }
    if best {
        lines.append("Prices and stock are rechecked before you accept. Product matches, steps and opening hours are in the Options step.");
    } else {
        lines.append("Tell me which travel, time or carrying limit you can change, and I will compare again.");
    }
    return "\n".join(lines);
}
