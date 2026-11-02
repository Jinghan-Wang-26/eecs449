"""Real-store visit rules: historical evidence matching, bounded store choice,
route choice and the single-store visit proposal.

`planning/visits.py` keeps only provider calls, concurrency and timing and
passes their results here. Historical records are reference evidence: they
never become current prices, stock or a budget guarantee.
"""

import hashlib;
import json;
import math;
import re;
import uuid;
import from datetime { date }
import from urllib.parse { urlencode }
import from app_settings { instant, stamp }
import from integrations.openprices { CATEGORY_TAGS }
import from ai.matching { satisfies_requested_spec }

glob ALIASES: dict[str, str] = {"yoghurt": "yogurt", "egg": "eggs"},
     SUPPORTED: list[str] = ["WALK", "BIKE", "CAR", "BUS"],
     DISCLAIMER: str = "Historical observations only. Today's prices, stock and opening hours are unverified. Confirm package size, diet requirements and prices before buying.",
     # Common ingredient/derivative false positives for staple requests.
     EXCLUSIONS: dict[str, list[str]] = {
         "milk": ["chocolate", "powder", "soap", "tea", "coconut", "almond", "soy", "soya", "oat", "oats", "cashew", "rice", "condensed", "evaporated"],
         "rice": ["cake", "cakes", "cracker", "crackers", "noodles", "cereal"],
         "eggs": ["chocolate"]
     },
     MAX_RETAILERS: int = 3,
     MAX_WITH_HISTORY: int = 4,
     MAX_STORES: int = 6,
     SHOPPING_MIN: int = 20;

def signature(context: dict) -> str {
    return hashlib.sha256(json.dumps(context, sort_keys=True, ensure_ascii=False).encode()).hexdigest();
}

def words(value: any) -> set[str] {
    return set(re.findall(r"[a-z0-9]+", str(value).casefold()));
}

def search_term(category: str) -> str {
    return ALIASES.get(category, category);
}

"""Does a historical record plausibly satisfy the need? Name or category tag,
no excluded derivative words, requested brand/size, every dietary tag, and a
record date that is not in the future."""
def match_record(need: dict, record: dict, dietary: list, now: str) -> bool {
    query = search_term(str(need["type"])).casefold();
    name = str(record.get("name", "")).casefold();
    terms = words(query);
    tagged = CATEGORY_TAGS.get(query) in record.get("categories", []);
    if not terms or (not terms.issubset(words(name)) and not tagged) { return False; }
    if words(name) & set(EXCLUSIONS.get(query, [])) { return False; }
    if not satisfies_requested_spec(need, record.get("brand", ""), record.get("size_label", ""), record.get("name", "")) { return False; }
    labels = {str(x).removeprefix("en:") for x in record.get("labels", [])};
    if any([str(tag).removeprefix("en:") not in labels for tag in dietary]) { return False; }
    try {
        return date.fromisoformat(record["recorded_on"]) <= instant(now).date();
    } except (ValueError, TypeError, KeyError) {
        return False;
    }
}

def is_retailer(store: dict) -> bool {
    return store.get("source") == "kroger" and bool(store.get("product_access"));
}

"""Bound provider work while keeping history-backed and location-only options:
up to 3 retailer branches, history-backed stores up to 4 in total, then the
nearest remaining stores up to 6. Extra retailer branches are never added as
location-only visits."""
def choose_stores(nearby: list) -> list {
    retailer = [s for s in nearby if is_retailer(s)][:MAX_RETAILERS];
    history = [s for s in nearby if s.get("source") == "openprices"][:max(0, MAX_WITH_HISTORY - len(retailer))];
    chosen = retailer + history;
    for store in nearby {
        if len(chosen) >= MAX_STORES { break; }
        if is_retailer(store) and store["id"] not in [s["id"] for s in retailer] { continue; }
        if store["id"] not in [s["id"] for s in chosen] { chosen.append(store); }
    }
    return chosen;
}

def unsupported_mode_notice(mode: str) -> str {
    return mode + ": no verified public-transit/rideshare estimate available.";
}

"""Combine a road estimate and its schedule into a route candidate."""
def road_candidate(mode: str, travel: dict, schedule: dict, profile: dict) -> dict {
    violations = [];
    if mode == "WALK" and travel["walk_min"] > profile["max_walk_min"] {
        violations.append("Walking segment exceeds your walking limit.");
    }
    if schedule["blocker"] { violations.append(schedule["blocker"]); }
    return travel | {"mode": mode, "total_min": int(travel["min"]) + SHOPPING_MIN, "shopping_min": SHOPPING_MIN}
                  | schedule | {"violations": violations};
}

"""Prefer a route without violations, then the shortest total time."""
def best_route(candidates: list) -> any {
    if not candidates { return None; }
    return min(candidates, key=lambda c: dict: (bool(c["violations"]), c["total_min"]));
}

def usable_number(value: any) -> bool {
    return type(value) in [int, float] and math.isfinite(value);
}

def visit_warnings(store: dict, evidence: dict, travel: any, profile: dict, counts: dict, subtotal: float) -> list {
    needs = counts["needs"];
    warnings = [DISCLAIMER];
    if store.get("details_notice") { warnings.append(store["details_notice"]); }
    if travel {
        if travel["timezone_notice"] { warnings.append(travel["timezone_notice"]); }
        if travel["hours_status"] == "REGULAR_HOURS_FIT" {
            warnings.append("The suggested visit fits recorded regular opening hours. Holiday exceptions and unexpected closures still need checking.");
        } else {
            warnings.append("Opening hours are missing, unsupported or do not fit your available time. Check the store before travelling.");
        }
        warnings.append(travel["notice"] if travel["mode"] == "BUS" else "Future travel uses a current route estimate, not a traffic forecast. Refresh before departure.");
    }
    if counts["matched"] < needs { warnings.append(f"{needs - counts['matched']} shopping need(s) have no matching evidence in the checked records."); }
    if evidence.get("partial") { warnings.append("Historical search coverage is partial; unmatched does not mean unavailable."); }
    if counts["priced"] < needs { warnings.append("Reference subtotal excludes missing, discounted, non-USD and non-package prices."); }
    if profile["weekly_budget"] <= 0 {
        warnings.append("Set a budget to compare against the historical reference subtotal.");
    } elif subtotal > profile["weekly_budget"] {
        warnings.append("Even the partial historical reference subtotal exceeds your saved budget.");
    }
    warnings.append("Current budget feasibility is unknown; reference amounts exclude tax, fees and transport.");
    if counts["weighed"] < needs { warnings.append("Full carrying weight is unknown; available net weights exclude packaging."); }
    if travel and travel["mode"] == "CAR" and profile["transport_cost"] < 0 {
        warnings.append("Driving cost is unknown; enter an estimate in your profile.");
    }
    if evidence.get("notice") { warnings.append(evidence["notice"]); }
    return warnings;
}

"""A single-store visit proposal from historical evidence and a chosen route.
Retailer quotes are applied afterwards by planning/retail.jac."""
def history_candidate(store: dict, evidence: dict, travel: any, route_errors: list, context: dict, now: str) -> dict {
    needs = context["needs"];
    profile = context["profile"];
    items = [];
    matched = 0; priced = 0; weighed = 0;
    subtotal = 0.0; known_mass = 0.0;
    for need in needs {
        matches = [row for row in evidence["records"]
                   if str(row.get("location_id")) == str(store.get("external_id"))
                   and match_record(need, row, profile["dietary"], now)];
        matches.sort(key=lambda x: dict: (x["recorded_on"], x["record_id"]), reverse=True);
        record = matches[0] if matches else None;
        item = {"category": need["type"], "qty": need["qty"], "outcome": "PENDING", "evidence": record,
                "reference_amount": None, "match_note": "No matching evidence in the checked records; check at the store."};
        if record {
            matched += 1;
            item["match_note"] = "Name/spec matches a historical record; product suitability and stock still require your confirmation.";
            # A per-kg/per-L record cannot be multiplied by a package count.
            price = record.get("price");
            if record.get("price_per") == "UNIT" and record.get("currency") == "USD" and not record.get("discounted")
               and usable_number(price) and price >= 0 {
                item["reference_amount"] = round(price * need["qty"], 2);
                subtotal += item["reference_amount"];
                priced += 1;
            }
            weight = record.get("weight_kg");
            if usable_number(weight) and weight > 0 {
                known_mass += weight * need["qty"];
                weighed += 1;
            }
        }
        items.append(item);
    }
    blockers = list(travel["violations"]) if travel else ["No supported route could be verified."];
    if known_mass > profile["carry_limit_kg"] { blockers.append("Known net product mass already exceeds your carrying limit."); }
    subtotal = round(subtotal, 2);
    counts = {"needs": len(needs), "matched": matched, "priced": priced, "weighed": weighed};
    warnings = visit_warnings(store, evidence, travel, profile, counts, subtotal);
    nav_mode = {"WALK": "walking", "BIKE": "bicycling", "CAR": "driving", "BUS": "transit"}.get(travel["mode"] if travel else "", "walking");
    origin = context["origin"];
    navigation = "https://www.google.com/maps/dir/?" + urlencode({"api": 1, "origin": f'{origin["lat"]},{origin["lon"]}',
        "destination": f'{store["lat"]},{store["lon"]}', "travelmode": nav_mode});
    reason = f'{store["name"]}: {matched}/{len(needs)} needs have matching historical evidence.';
    if travel { reason += f' Estimated {travel["min"]} minutes round trip by {travel["mode"]}, plus 20 minutes shopping.'; }
    reason += " Ranked by route/time eligibility, historical match coverage, then trip duration and distance; not by today's price.";
    return {"key": str(uuid.uuid4()), "kind": "HISTORICAL_STORE_VISIT", "status": "PROPOSED", "created_at": stamp(now),
            "input_signature": signature(context), "origin_label": origin.get("address", "Confirmed location"),
            "store": store, "items": items, "matched": matched, "need_count": len(needs), "route": travel,
            "reference_subtotal": subtotal if priced else None, "priced_needs": priced,
            "known_net_weight_kg": round(known_mass, 2) if weighed else None, "weight_complete": weighed == len(needs),
            "blockers": blockers, "warnings": warnings, "route_notices": route_errors, "accept_allowed": not blockers,
            "explanation": reason, "navigation_url": navigation, "checked_records": evidence["checked"]};
}

"""Re-schedule road visits against the time provider lookups finished. A bus
timetable is fixed, so a passed departure blocks instead of sliding."""
def recheck_after_lookup(plan: dict, schedule: any, ready: str) -> dict {
    travel = plan["route"];
    if not travel { return plan; }
    if travel["mode"] == "BUS" {
        if instant(travel["departure_at"]) <= instant(ready) or instant(travel["valid_until"]) <= instant(ready) {
            plan["blockers"].append("Scheduled departure passed or transit evidence expired during lookup. Refresh recommendations.");
            travel["violations"] = list(plan["blockers"]);
        }
    } else {
        previous = travel.get("blocker", "");
        plan["blockers"] = [b for b in plan["blockers"] if not previous or b != previous];
        travel["violations"] = [b for b in travel["violations"] if not previous or b != previous];
        travel.update(schedule);
        if schedule["blocker"] {
            plan["blockers"].append(schedule["blocker"]);
            travel["violations"].append(schedule["blocker"]);
        }
        if instant(travel["valid_until"]) < instant(ready) {
            plan["blockers"].append("Route estimate expired during lookup. Refresh recommendations.");
        }
    }
    plan["accept_allowed"] = not plan["blockers"];
    plan["created_at"] = stamp(ready);
    return plan;
}

def search_notice(chosen: int, nearby: int, compared: int) -> str {
    return f"Checked {chosen} of {nearby} nearby stores; compared {compared} bounded single-store, two-store and entered-delivery options. This is a bounded search, not an exhaustive inventory comparison.";
}

"""Route rechecked with the price refresh must still be valid and in the future."""
def refreshed_route_blocker(travel: any, checked: str) -> str {
    if not travel or instant(travel["valid_until"]) <= instant(checked)
       or (travel.get("departure_at") and instant(travel["departure_at"]) <= instant(checked)) {
        return "Route expired or departure passed during price verification. Generate new recommendations.";
    }
    return "";
}
