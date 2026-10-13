"""Manual checks and an in-app inbox; no background scheduler required."""

import from app_settings { get_settings, stamp, due, later, elapsed_hours, quiet }
import from models.profile { UserProfile }
import from models.interest { InterestItem, InterestKind, InterestStatus }
import from models.catalog { Offer, Availability }
import from models.plan { ShoppingPlan, PlanStatus }
import from models.events { SyncState, ReminderStatus }
import from models.graph { Has, owned, catalog_of, items_of, add_reminder, reminders_of, about_of }
import from planning.inputs { products_for }
import from models.graph { offers_of, store_of, product_of }

def awake(item: InterestItem, now: str) -> bool {
    return item.status == InterestStatus.ACTIVE and (item.snoozed_until == "" or due(item.snoozed_until, now));
}

def offer_snapshot(p: UserProfile, now: str) -> dict {
    cat = catalog_of(p);
    out = {};
    for o in [cat ->:Has:->][?:Offer] {
        out[o.key] = {"price": o.price_for(p.memberships), "stock": o.availability.name,
                      "fresh": o.is_fresh(now), "observed_at": o.observed_at};
    }
    return out;
}

def emit_once(p: UserProfile, key: str, kind: str, message: str, now: str, about: list, cooldown: int) -> any {
    if any([r.dedup_key == key for r in reminders_of(p)]) { return None; }
    return add_reminder(p, key, kind, message, now, about, now, cooldown);
}

def check_reminders(p: UserProfile, now: str, settings: dict = {}) -> list {
    cfg = get_settings(settings);
    now = stamp(now, cfg);
    state = owned(p, SyncState);
    added = [];
    for item in items_of(p) {
        if not awake(item, now) or item.kind == InterestKind.DISCOVER {
            continue;
        }
        name = item.product_spec.get("type", "item");
        if item.kind == InterestKind.REPLENISH and item.replenishment_days > 0 and item.last_purchased_at != "" {
            if elapsed_hours(item.last_purchased_at, now, cfg) >= item.replenishment_days * 24 {
                key = "replenish:" + name + ":" + item.last_purchased_at;
                r = emit_once(p, key, "REPLENISH", "You may be running low on " + name + ". Add it?",
                                 now, [item], cfg["reminder_cooldown_hours"]);
                if r is not None { added.append(r); }
            }
        }
        if item.kind != InterestKind.WATCH {
            continue;
        }
        for prod in products_for(item, catalog_of(p)) {
            for o in offers_of(prod) {
                if not o.is_fresh(now) or o.availability not in [Availability.IN_STOCK, Availability.LOW] {
                    continue;
                }
                price = o.price_for(p.memberships);
                store = store_of(o);
                detail = f"{prod.name} at {store.name} ({o.channel}); observed {o.observed_at}. Simulated data.";
                if price is not None and item.target_price > 0 and price <= item.target_price {
                    key = f"price:{name}:{o.key}:{item.target_price}:{price}";
                    membership = " Membership price: " + o.member_program + "." if price == o.member_price and o.member_program in p.memberships else "";
                    r = emit_once(p, key, "PRICE_DROP", f"Target price reached: ${price:.2f}. " + detail + membership,
                                     now, [item, o], cfg["reminder_cooldown_hours"]);
                    if r is not None { added.append(r); }
                }
                before = state.observations.get(o.key, {});
                if before.get("stock") == "OUT" and before.get("fresh", False) {
                    key = "restock:" + name + ":" + o.key + ":" + o.observed_at;
                    r = emit_once(p, key, "RESTOCK", "Back in stock: " + detail, now, [item, o], cfg["reminder_cooldown_hours"]);
                    if r is not None { added.append(r); }
                }
            }
        }
    }
    state.observations = offer_snapshot(p, now);
    return added;
}

def actionable(r: any, now: str) -> bool {
    for n in about_of(r) {
        if isinstance(n, ShoppingPlan) and r.kind == "PLAN_CHANGE" and n.status != PlanStatus.NEEDS_REVIEW { return False; }
        if isinstance(n, InterestItem) {
            if r.kind in ["PRICE_DROP", "RESTOCK"] and (n.kind != InterestKind.WATCH or (n.last_purchased_at != "" and due(r.created_at, n.last_purchased_at))) { return False; }
            if r.kind == "REPLENISH" and n.kind != InterestKind.REPLENISH { return False; }
            if not awake(n, now) { return False; }
            if r.kind == "REPLENISH" and (n.last_purchased_at == "" or not r.dedup_key.endswith(n.last_purchased_at)) { return False; }
        }
        if isinstance(n, Offer) and r.kind in ["PRICE_DROP", "RESTOCK"] {
            if not n.is_fresh(now) or n.availability not in [Availability.IN_STOCK, Availability.LOW] { return False; }
        }
    }
    return True;
}

def inbox(p: UserProfile, now: str, settings: dict = {}) -> list {
    cfg = get_settings(settings);
    if quiet(now, cfg) { return []; }
    out = [];
    for r in reminders_of(p) {
        if r.status not in [ReminderStatus.PENDING, ReminderStatus.SNOOZED, ReminderStatus.SENT] or not due(r.fire_at, now, cfg) or not actionable(r, now) {
            continue;
        }
        # Do not display a stale target-price claim after the offer changes.
        if r.kind == "PRICE_DROP" {
            needs = [n for n in about_of(r) if isinstance(n, InterestItem)];
            offers = [n for n in about_of(r) if isinstance(n, Offer)];
            if not needs or not offers { continue; }
            price = offers[0].price_for(p.memberships);
            if price is None or price > needs[0].target_price or not r.dedup_key.endswith(":" + str(price)) { continue; }
        }
        if r.status != ReminderStatus.SENT {
            r.status = ReminderStatus.SENT;
            r.last_sent_at = stamp(now, cfg);
        }
        out.append({"key": r.dedup_key, "kind": r.kind, "message": r.message});
    }
    return out;
}

def reminder_action(p: UserProfile, key: str, action: str, now: str, settings: dict = {}) -> bool {
    cfg = get_settings(settings);
    if action not in ["dismiss", "snooze", "ignore", "add"] {
        raise ValueError("Reminder action must be dismiss, snooze, ignore, or add");
    }
    for r in reminders_of(p) {
        if r.dedup_key != key or r.status == ReminderStatus.DISMISSED { continue; }
        if action == "add" {
            if not actionable(r, now) { return False; }
            if r.kind == "PRICE_DROP" and key not in [card["key"] for card in inbox(p, now, cfg)] { return False; }
            for n in about_of(r) {
                if isinstance(n, InterestItem) {
                    if n.kind == InterestKind.WATCH { n.kind = InterestKind.NEED; }
                    n.snoozed_until = "";
                }
            }
            r.status = ReminderStatus.DISMISSED;
        } elif action == "dismiss" {
            r.status = ReminderStatus.DISMISSED;
        } else {
            if action == "ignore" { r.ignored_count += 1; }
            r.status = ReminderStatus.SNOOZED;
            r.fire_at = later(now, max(1, cfg["reminder_cooldown_hours"]) * (1 + min(r.ignored_count, 3)), cfg);
        }
        return True;
    }
    return False;
}
