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
    if not modes or (context["data_mode"] == "live" and not any([m in ["WALK", "BIKE", "CAR"] for m in modes])) { missing.append("transport"); }
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
        "transport": "Your saved transport cannot produce a verified route. Can you walk, cycle or drive? If bus is your only option, tell me; I will keep that constraint.",
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
        specs = [f"{k}: {n[k] or '(cleared)'}" for k in ['brand', 'size'] if k in n];
        parts.append(detail + (" (" + ", ".join(specs) + ")" if specs else ""));
    }
    if not parts { return ""; }
    prefix = "Updated your shopping information: ";
    return prefix + "; ".join(parts) + ".\n";
}

def plan_summary(workspace: dict, lang: str) -> str {
    plans = [p for p in workspace["visit_plans"] if p["status"] == "PROPOSED"];
    if not plans {
        notices = "\n".join(workspace.get("notices", []));
        if notices { return notices; }
        return "No nearby stores were found. Try a wider radius or another starting address.";
    }
    eligible = len([p for p in plans if p["accept_allowed"]]);
    title = f"Found {len(plans)} store options; {eligible} can be reviewed and accepted:";
    lines = [title];
    for (i,p) in enumerate(plans) {
        items = ", ".join([f"{x['qty']} × {x['category']}" for x in p["items"]]);
        lines.append(f"{i+1}. {p['store']['name']} — {p['store']['address']}\n   {items}");
        if p["route"] {
            t = p["route"];
            lines.append(f"   {t['mode']}: {t['min']} min round trip + {t['shopping_min']} min shopping; {t['window'] or 'no fitting time window'}");
        }
        coverage = f"   Historical matches: {p['matched']}/{p['need_count']}; ";
        price = f"USD {p['reference_subtotal']} historical reference (not today's total)" if p["reference_subtotal"] is not None else "price unknown";
        lines.append(coverage + price);
        if p["blockers"] { lines.append("   " + "; ".join(list(p["blockers"]) + list(p["route_notices"]))); }
    }
    lines.append("Current prices, stock and opening hours remain unknown. Missing historical evidence does not mean out of stock. Review evidence and accept a visit in the shopping panel.");
    if not eligible {
        lines.append("These options are blocked. Tell me which travel, time or carrying constraints you can change, and I will rebuild the plan.");
    }
    return "\n".join(lines);
}
