"""Address, profile, live catalog, and plan operations on the user's graph."""

import uuid;
import from server.visits { recommend_visits, visit_action, visit_view, invalidate_visits, delivery_operation }
import from pricing { price_details }
import from ai.matching { rank_products }
import json;
import hashlib;
import from app_settings { get_settings, stamp, due }
import from integrations.providers { geocode, nearby, products, route, credential_status, credentials, reverse_geocode }
import from integrations.openprices { nearby_with_history, price_records }
import from integrations.validation { profile_patch, need_spec, number }
import from models.profile { UserProfile }
import from models.catalog { Product, Store, Offer, Availability }
import from models.interest { InterestKind, InterestStatus }
import from models.plan { PlanStatus }
import from models.events { ShoppingWorkspace }
import from models.graph { Has, Wants, UsesOffer, product_of, store_of, owned, catalog_of, items_of, add_need, plans_of, plan_items_of, upsert_store, upsert_product, upsert_offer, find_in, want, offer_of, plan_changes }
import from planning.lifecycle { plan_shopping, accept }
import from sync.engine { sync_events }


def mode_of(p: UserProfile) -> str {
    return p.data_mode if p.data_mode != "" else get_settings()["data_mode"];
}

def invalidate_plans(p: UserProfile, message: str) -> None {
    invalidate_visits(p, message);
    for plan in plans_of(p) {
        if plan.status in [PlanStatus.DRAFT, PlanStatus.PROPOSED] {
            plan.move_to(PlanStatus.CANCELLED);
        } elif plan.status in [PlanStatus.ACCEPTED, PlanStatus.IN_PROGRESS] {
            plan.move_to(PlanStatus.NEEDS_REVIEW);
            plan.explanation += "\nNeeds review: " + message;
        }
    }
}

def save_need(p: UserProfile, data: dict) -> any {
    spec = need_spec(data);
    found = [n for n in items_of(p) if n.kind != InterestKind.DISCOVER and n.product_spec.get("type") == spec["type"]];
    if not found and len([n for n in items_of(p) if n.plannable()]) >= 6 {
        raise ValueError("Use at most six active shopping needs in this prototype.");
    }
    item = found[0] if found else add_need(p, spec);
    if found {
        fresh_list = not getattr(item, "in_current_list", True);
        merged = dict(spec) if fresh_list else dict(item.product_spec);
        for field in ["qty", "brand", "size", "variant"] {
            if field in data { merged[field] = spec[field]; }
        }
        if fresh_list or any([merged.get(field, "") != item.product_spec.get(field, "") for field in ["brand", "size", "variant"]]) {
            for link in [edge item ->:Wants:->] { link.confirmed = False; }
        }
        item.product_spec = merged;
        if fresh_list {
            item.snoozed_until = ""; item.needed_by = ""; item.priority = 2;
        }
    }
    item.in_current_list = True;
    item.status = InterestStatus.ACTIVE;
    item.source = "USER";
    return item;
}

def start_new_plan(p: UserProfile, request_id: str, now: str) -> str {
    try { uuid.UUID(request_id); }
    except (ValueError, TypeError, AttributeError) { raise ValueError("A new plan needs a valid request ID."); }
    state = owned(p, ShoppingWorkspace);
    requests = list(getattr(state, "new_plan_request_ids", []));
    if request_id in requests { return "This new shopping plan was already started."; }
    history = list(getattr(state, "visit_history", []));
    keys = {v["key"] for v in history};
    for plan in state.visit_plans {
        if plan["status"] not in ["COMPLETED", "CANCELLED"] {
            plan["status"] = "CANCELLED"; plan["closed_at"] = now;
            plan["review_reason"] = "A new shopping plan was explicitly started.";
        }
        if plan.get("accepted_at") and plan["key"] not in keys {
            history.append(plan); keys.add(plan["key"]);
        }
    }
    state.visit_history = history; state.visit_plans = []; state.visit_search = {}; state.delivery_quotes = [];
    for plan in plans_of(p) {
        if plan.status not in [PlanStatus.COMPLETED, PlanStatus.CANCELLED] { plan.move_to(PlanStatus.CANCELLED); }
    }
    for item in items_of(p) {
        if item.kind in [InterestKind.NEED, InterestKind.REPLENISH] {
            item.in_current_list = False;
            if item.status == InterestStatus.ACTIVE { item.status = InterestStatus.PAUSED; }
        }
    }
    state.chat_planning = True; state.chat_address_pending = False;
    state.pending_intent = {}; state.pending_id = ""; state.address_candidates = [];
    state.product_results = []; state.historical_prices = {}; state.notices = [];
    state.chat_question = "What would you like to buy for this new trip, and how many packages of each?";
    reply = ("Started a new shopping plan with an empty list. Your address and preferences are saved; previous needs are paused.\n") + state.chat_question;
    state.chat_messages = [{"role":"assistant", "content":reply}];
    state.new_plan_request_ids = (requests + [request_id])[-100:];
    return reply;
}

def select_location(p: UserProfile, candidate_id: str) -> None {
    state = owned(p, ShoppingWorkspace);
    candidates = [c for c in state.address_candidates if c["id"] == candidate_id];
    if len(candidates) != 1 { raise ValueError("Search the address again, then choose one result."); }
    chosen = candidates[0];
    if p.location != chosen {
        invalidate_plans(p, "The shopping address changed. Search nearby stores again.");
        # Remove routes tied to the previous origin, without losing historical plans.
        cat = catalog_of(p);
        for store in [cat ->:Has:->][?:Store] {
            if store.mode == "live" { store.routes = {}; store.channels = []; }
        }
        state.nearby_stores = [];
        state.product_results = [];
        state.historical_prices = {};
    }
    p.location = dict(chosen);
    p.home_address = chosen["address"];
    state.address_candidates = [];
    state.chat_address_pending = False;
}

def import_results(p: UserProfile, store: dict, need: any, rows: list) -> list {
    cat = catalog_of(p);
    if cat.mode != "live" { raise ValueError("Live data cannot be added to the mock catalog."); }
    s = upsert_store(cat, store["id"], {"name": store["name"], "address": store["address"],
        "external_id": store["external_id"], "latitude": store["lat"], "longitude": store["lon"],
        "hours": store.get("hours", {}), "mode": "live", "origin_key": p.location["id"], "channels": ["IN_STORE"]});
    events = [];
    for row in rows {
        prod = upsert_product(cat, row["key"], {"name": row["name"], "brand": row["brand"],
            "external_id": row["external_id"], "size_label": row["size_label"], "category": need.product_spec["type"]});
        if row["weight_kg"] is not None { prod.weight_kg = row["weight_kg"]; prod.weight_known = True; }
        elif prod.weight_kg <= 0 { prod.weight_known = False; }
        if not [edge need ->:Wants:-> prod] { want(need, prod, substitute=True, confirmed=False); }
        existing = find_in(cat, Offer, s.key + ":" + prod.key + ":IN_STORE");
        fields = {"price": row["price"], "availability": row["availability"],
                  "observed_at": row["observed_at"], "valid_until": row["valid_until"]};
        if existing is None {
            upsert_offer(cat, s, prod, "IN_STORE", {"price": row["price"], "availability": Availability[row["availability"]],
                "observed_at": row["observed_at"], "valid_until": row["valid_until"], "source": "kroger", "mode": "live"});
        } else {
            signature = hashlib.sha256(json.dumps({"key": existing.key, "fields": fields}, sort_keys=True).encode()).hexdigest();
            events.append({"id": "kroger:" + signature, "type": "offer", "key": existing.key, "fields": fields});
        }
    }
    return events;
}

def fetch_products(p: UserProfile, store_id: str, category: str, batch: list | None = None) -> list {
    if mode_of(p) != "live" { raise ValueError("Switch to live mode before searching real products."); }
    state = owned(p, ShoppingWorkspace);
    stores = [s for s in state.nearby_stores if s["id"] == store_id and s.get("product_access", False) and s.get("source") == "kroger"];
    needs = [n for n in items_of(p) if n.status == InterestStatus.ACTIVE and n.kind != InterestKind.DISCOVER and n.product_spec.get("type") == category];
    if not stores or not needs { raise ValueError("Select a supported nearby store and save the shopping need first."); }
    rows = products(stores[0]["external_id"], category);
    rows = rank_products(needs[0].product_spec, [r for r in rows if r["in_store"]]);
    events = import_results(p, stores[0], needs[0], rows);
    if batch is not None { batch.extend(events); }
    elif events { sync_events(p, events, stamp(), {"data_mode": "live"}); }
    for row in rows {
        row["store_key"] = store_id;
        row["result_id"] = store_id + "|" + row["key"];
    }
    state.product_results = rows;
    return rows;
}

def refresh_live(p: UserProfile) -> list {
    state = owned(p, ShoppingWorkspace);
    notices = [];
    batch = [];
    stores = [s for s in state.nearby_stores if s.get("product_access", False) and s.get("source") == "kroger"][:3];
    needs = [n for n in items_of(p) if n.status == InterestStatus.ACTIVE and n.kind != InterestKind.DISCOVER][:6];
    for s in stores {
        for n in needs {
            try { fetch_products(p, s["id"], n.product_spec["type"], batch); }
            except ValueError as err { notices.append(str(err)); }
        }
    }
    if batch { sync_events(p, batch, stamp(), {"data_mode": "live"}); }
    state.notices = notices;
    return notices;
}

def prepare_routes(p: UserProfile, now: str) -> list {
    if not p.location { raise ValueError("Confirm an address before building a live plan."); }
    notices = [];
    cat = catalog_of(p);
    for s in [cat ->:Has:->][?:Store] {
        if s.mode != "live" or s.origin_key != p.location["id"] { continue; }
        routes = {};
        for transport in p.transport {
            try {
                r = route([p.location["lat"], p.location["lon"]], [s.latitude, s.longitude], transport);
                if r["cost"] is None {
                    if p.transport_cost < 0 { raise ValueError("Enter an estimated round-trip transport cost for driving."); }
                    r["cost"] = p.transport_cost;
                }
                routes[transport] = r;
            } except ValueError as err { notices.append(str(err)); }
        }
        s.routes = routes;
    }
    return notices;
}

def plan_action(p: UserProfile, key: str, action: str, now: str = "") -> None {
    found = [plan for plan in plans_of(p) if plan.key == key and plan.mode == mode_of(p)];
    if len(found) != 1 { raise ValueError("Plan not found in the active data mode."); }
    plan = found[0];
    if action == "accept" {
        if plan_changes(plan, now, p.memberships) { raise ValueError("Plan quotes changed or expired. Refresh and compare plans again."); }
        if plan.status == PlanStatus.NEEDS_REVIEW { raise ValueError("Build and review a new plan before accepting changed conditions."); }
        if not accept(p, plan) { raise ValueError("This plan cannot be accepted in its current state."); }
    } elif action == "cancel" {
        if not plan.move_to(PlanStatus.CANCELLED) { raise ValueError("This plan cannot be cancelled."); }
    } else { raise ValueError("Plan action must be accept or cancel."); }
}

def workflow(p: UserProfile, action: str, data: dict, now: str) -> str {
    state = owned(p, ShoppingWorkspace);
    if action == "new_plan" {
        return start_new_plan(p, data.get("request_id"), now);
    } elif action == "set_mode" {
        mode = data.get("mode");
        if mode not in ["mock", "live"] { raise ValueError("Choose mock or live mode."); }
        if mode != mode_of(p) {
            invalidate_plans(p, "Data mode changed.");
            p.data_mode = mode;
            state.product_results = [];
            state.historical_prices = {};
        }
        return "Data mode: " + mode;
    } elif action == "update_profile" {
        patch = profile_patch(data);
        if any([getattr(p, k) != patch[k] for k in patch]) {
            invalidate_plans(p, "Shopping constraints changed.");
            for k in patch { setattr(p, k, patch[k]); }
        }
        return "Profile saved.";
    } elif action == "geocode" {
        if mode_of(p) != "live" { raise ValueError("Switch to live mode to resolve a real address."); }
        state.address_candidates = geocode(data.get("address", ""));
        return "Choose the intended address." if state.address_candidates else "No address match found. Add a city or ZIP code.";
    } elif action == "device_location" {
        if mode_of(p) != "live" { raise ValueError("Choose Real stores to use your location."); }
        state.address_candidates = reverse_geocode(number(data.get("lat"), -90, 90, "latitude"), number(data.get("lon"), -180, 180, "longitude"), number(data.get("accuracy_m", 0), 0, 100000, "location accuracy"));
        return "Review and confirm the address for your device location.";
    } elif action == "confirm_address" {
        select_location(p, data.get("id", ""));
        return "Address confirmed. You can now search nearby stores.";
    } elif action == "nearby" {
        if mode_of(p) != "live" or not p.location { raise ValueError("Confirm an address in live mode first."); }
        radius = int(number(data.get("radius_m", state.search_radius_m), 500, 20000, "radius"));
        if radius != state.search_radius_m { invalidate_visits(p, "Search radius changed."); }
        state.search_radius_m = radius;
        result = nearby_with_history(p.location["lat"], p.location["lon"], radius, include_kroger=False);
        state.nearby_stores = result["stores"];
        state.notices = result["notices"];
        return f"Found {len(state.nearby_stores)} nearby stores. Product access is shown per store.";
    } elif action == "historical_prices" {
        stores = [s for s in state.nearby_stores if s["id"] == data.get("store") and s.get("source") == "openprices"];
        if mode_of(p) != "live" or len(stores) != 1 { raise ValueError("Choose an Open Prices store from your nearby results."); }
        result = price_records(stores[0]["external_id"], data.get("page", 1));
        result["store_name"] = stores[0]["name"];
        result["store_key"] = stores[0]["id"];
        state.historical_prices = result;
        return "Historical price records loaded. These do not confirm current prices or inventory.";
    } elif action == "store_route" {
        stores = [s for s in state.nearby_stores if s["id"] == data.get("store")];
        if mode_of(p) != "live" or not p.location or len(stores) != 1 { raise ValueError("Choose a nearby store after confirming your address."); }
        travel = route([p.location["lat"], p.location["lon"]], [stores[0]["lat"], stores[0]["lon"]], data.get("transport", "WALK"));
        state.notices = [stores[0]["name"] + f": estimated {travel['min']} round-trip minutes by {data.get('transport', 'WALK')}. Source: Geoapify. This is a travel estimate, not a shopping plan or transit timetable."];
        return state.notices[0];
    } elif action == "search_products" {
        rows = fetch_products(p, data.get("store", ""), data.get("category", ""));
        return f"Found {len(rows)} store-specific products. Confirm suitable matches before planning.";
    } elif action == "confirm_product" {
        found = [r for r in state.product_results if r["result_id"] == data.get("id")];
        if not found or mode_of(p) != "live" { raise ValueError("Search products again before confirming this match."); }
        row = found[0];
        if not due(now, row["valid_until"]) { raise ValueError("This quote expired. Search again."); }
        prod = find_in(catalog_of(p), Product, row["key"]);
        weight = data.get("weight_kg");
        if weight is not None and weight != "" { prod.weight_kg = number(weight, 0.001, 100, "package weight"); prod.weight_known = True; }
        for n in items_of(p) {
            if n.product_spec.get("type") == row["search_term"] and n.status == InterestStatus.ACTIVE and n.kind != InterestKind.DISCOVER {
                want(n, prod, substitute=True, confirmed=True);
            }
        }
        invalidate_plans(p, "Product match changed.");
        return "Product match confirmed.";
    } elif action in ["save_delivery_quote", "remove_delivery_quote"] {
        return delivery_operation(p, action, data, now);
    } elif action == "recommend_visits" {
        radius = int(number(data.get("radius_m", state.search_radius_m), 500, 20000, "radius"));
        if radius != state.search_radius_m { invalidate_visits(p, "Search radius changed."); }
        state.search_radius_m = radius;
        return recommend_visits(p, now);
    } elif action == "visit_action" {
        return visit_action(p, data, now);
    } elif action == "plan" and mode_of(p) == "live" {
        return recommend_visits(p, now);
    } elif action in ["plan", "current_price_plan"] {
        if mode_of(p) == "live" {
            state.notices = prepare_routes(p, now);
            if p.tax_rate < 0 { raise ValueError("Enter a tax-rate estimate in your profile before live cost planning."); }
        }
        result = plan_shopping(p, now);
        return result["message"];
    } elif action == "plan_action" {
        plan_action(p, data.get("key", ""), data.get("action", ""), now);
        return "Plan updated.";
    }
    raise ValueError("Unknown workflow operation.");
}


def plan_item_view(pi: any) -> dict {
    out = {"name": pi.name, "qty": pi.qty, "outcome": pi.outcome.name};
    o = offer_of(pi);
    if o is None { return out | price_details(None); }
    prod = product_of(o);
    snapshots = [edge pi ->:UsesOffer:-> o];
    price = snapshots[0].price_at_plan if snapshots else None;
    out.update(price_details(price, prod.size, prod.unit, prod.size_label));
    out["product"] = prod.name;
    out["store"] = store_of(o).name;
    return out;
}

def workspace_view(p: UserProfile, now: str = "") -> dict {
    state = owned(p, ShoppingWorkspace);
    plans = [];
    for plan in plans_of(p) {
        if plan.mode != mode_of(p) or plan.status == PlanStatus.CANCELLED { continue; }
        plans.append({"key": plan.key, "status": plan.status.name, "strategy": plan.strategy.name,
            "total": plan.total, "cost": plan.cost, "minutes": plan.active_min, "weight": plan.carried_kg,
            "explanation": plan.explanation,
            "items": [plan_item_view(pi) for pi in plan_items_of(plan)]});
    }
    catalog_prices = [];
    cat = catalog_of(p);
    if cat.mode == "mock" {
        for o in [cat ->:Has:->][?:Offer] {
            prod = product_of(o);
            row = {"key": o.key, "category": prod.category, "name": prod.name,
                   "store": store_of(o).name, "channel": o.channel,
                   "observed_at": o.observed_at, "valid_until": o.valid_until,
                   "availability": o.availability.name,
                   "member_price_applied": o.member_program in p.memberships and o.member_price is not None};
            row.update(price_details(o.price_for(p.memberships), prod.size, prod.unit, prod.size_label));
            catalog_prices.append(row);
        }
    }
    products_view = [row | price_details(row.get("price"), label=row.get("size_label", "")) for row in state.product_results];
    return {"llm_backend": credentials().get("LLM_BACKEND", "api"), "catalog_prices": catalog_prices, "profile": {"address": p.home_address, "transport": p.transport, "budget": p.weekly_budget,
            "max_walk_min": p.max_walk_min, "max_transfers": p.max_transfers, "carry_limit_kg": p.carry_limit_kg, "free_windows": p.free_windows, "tax_rate": p.tax_rate,
            "transport_cost": p.transport_cost, "dietary": p.dietary, "memberships": p.memberships},
        "address_candidates": state.address_candidates, "stores": state.nearby_stores,
        "products": products_view, "plans": plans[-10:], "notices": state.notices,
        "shopping_needs": [dict(n.product_spec) for n in items_of(p) if n.plannable()],
        "delivery_quotes": list(getattr(state,"delivery_quotes",[])) if mode_of(p)=="live" else [],
        "visit_plans": visit_view(p, stamp(now)), "visit_search": state.visit_search, "search_radius_m": state.search_radius_m,
        "visit_history": list(getattr(state, "visit_history", [])) if mode_of(p) == "live" else [],
        "historical_prices": state.historical_prices,
        "pending_intent": state.pending_intent, "pending_id": state.pending_id,
        "credentials": credential_status()};
}
