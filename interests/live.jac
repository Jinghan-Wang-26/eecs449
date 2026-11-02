"""Real-store interest suggestions, emitted as reminders the shopper confirms.

Runs on Refresh, background checks and page loads, at most every CHECK_HOURS unless
forced. Retailer errors only skip the sale check; nothing is guessed.
"""

import from app_settings { get_settings, elapsed_hours }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace, SpendingLedger }
import from models.interest { InterestKind }
import from models.graph { owned, items_of }
import from notify.reminders { emit_once }
import from interests.suggest { purchase_days, usual_due, sale_categories, best_sale, search_term }
import from integrations.providers { nearby_kroger, products }
import from ai.matching { satisfies_requested_spec }

glob CHECK_HOURS: int = 6;

def listed_categories(p: UserProfile) -> list {
    return [n.product_spec.get("type", "") for n in items_of(p) if n.plannable()];
}

def live_suggestions(p: UserProfile, now: str, force: bool = False) -> int {
    state = owned(p, ShoppingWorkspace);
    last = getattr(state, "interest_checked_at", "");
    if not force and last and elapsed_hours(last, now) < CHECK_HOURS { return 0; }
    state.interest_checked_at = now;
    cooldown = get_settings()["reminder_cooldown_hours"];
    listed = listed_categories(p);
    visits = list(getattr(state, "visit_history", [])) + list(state.visit_plans);
    days = purchase_days(owned(p, SpendingLedger).entries, visits);
    created = 0;
    for row in usual_due(days, now, listed) {
        message = f"You usually buy {row['category']} about every {row['every']} days. Last bought {row['since']} days ago.";
        if emit_once(p, "usual|" + row["category"] + "|" + row["last"], "USUAL", message, now, [], cooldown) is not None { created += 1; }
    }
    if not p.location { return created; }
    specs = {};
    for n in items_of(p) {
        if n.kind != InterestKind.DISCOVER { specs[n.product_spec.get("type", "")] = n.product_spec; }
    }
    wanted = sale_categories(days, list(specs.keys()), listed);
    if not wanted { return created; }
    try {
        stores = nearby_kroger(p.location["lat"], p.location["lon"], state.search_radius_m);
    } except ValueError {
        return created;
    }
    if not stores { return created; }
    store = stores[0];
    for category in wanted {
        spec = specs.get(category, {"type": category});
        try { rows = products(store["external_id"], search_term(spec)); }
        except ValueError { continue; }
        found = best_sale(rows, lambda r: dict -> bool { return satisfies_requested_spec(spec, r["brand"], r["size_label"], r["name"]); });
        if found is None { continue; }
        item = found["row"];
        brand = item["brand"].replace("|", " ");
        key = "sale|" + category + "|" + brand + "|" + item["key"] + "|" + str(found["promo"]);
        message = f"{item['name']} is on sale at {store['name']}: ${found['promo']:.2f}, usually ${found['regular']:.2f}. Sale prices can end at any time.";
        if emit_once(p, key, "SALE", message, now, [], cooldown) is not None { created += 1; }
    }
    return created;
}
