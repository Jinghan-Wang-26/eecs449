"""Turn the user's Catalog (Store / Product / Offer) and needs into planning inputs.

Planning itself only sees Need, Channel, and Quote, so it can be tested without a catalog.
"""

import from models.profile { UserProfile }
import from models.interest { InterestItem }
import from models.catalog { Catalog, Store, Product, Offer, Availability }
import from models.graph { Has, Wants, catalog_of, items_of, usable_products, offers_of, product_of, store_of }
import from planning.types { Need, Channel, Quote, DAYS }

glob SHOP_MIN: dict = {"IN_STORE": 20, "PICKUP": 5},
     STOCK: dict = {"IN_STOCK": "YES", "LOW": "YES", "OUT": "NO", "UNKNOWN": "UNKNOWN"};

def need_key(item: InterestItem) -> str {
    return item.product_spec.get("type", "");
}

def needs_from_pool(p: UserProfile) -> list {
    out = [];
    for item in items_of(p) {
        if item.plannable() {
            out.append(Need(key=need_key(item), qty=item.product_spec.get("qty", 1), priority=item.priority));
        }
    }
    return out;
}

"""["MON", ..., "FRI"] from "MON-FRI"; ["SAT"] from "SAT"."""
def expand_days(spec: str) -> list {
    if "-" not in spec {
        return [spec];
    }
    ends = spec.split("-");
    return DAYS[DAYS.index(ends[0]):DAYS.index(ends[1]) + 1];
}

def hours_windows(hours: dict) -> list {
    out = [];
    for spec in hours {
        for day in expand_days(spec) {
            out.append(day + " " + hours[spec]);
        }
    }
    return out;
}

"""Fastest route the user can take this trip; if none is allowed, the fastest at all,
so the constraint check can say which mode the trip would need."""
def pick_route(s: Store, allowed: list) -> tuple {
    best = ("", {});
    fallback = ("", {});
    for mode in s.routes {
        r = s.routes[mode];
        if mode in allowed and (best[0] == "" or r["min"] < best[1]["min"]) {
            best = (mode, r);
        }
        if fallback[0] == "" or r["min"] < fallback[1]["min"] {
            fallback = (mode, r);
        }
    }
    return best if best[0] != "" else fallback;
}

def channels_for(cat: Catalog, ctx: dict) -> list {
    out = [];
    for s in [cat ->:Has:->][?:Store] {
        for kind in s.channels {
            cid = s.key + ":" + kind;
            if kind == "DELIVERY" {
                d = s.delivery;
                out.append(Channel(
                    id=cid, store=s.name, store_key=s.key, kind=kind,
                    windows=d.get("windows", []), covers_area=d.get("covers_area", True),
                    delivery_fee=d.get("fee", 0.0), fee_known=d.get("fee_known", True),
                    fee_max=d.get("fee_max", 0.0), service_fee_pct=d.get("service_pct", 0.0),
                    free_over=d.get("free_over", 0.0), min_order=d.get("min_order", 0.0),
                    tip=d.get("tip", 0.0)
                ));
                continue;
            }
            route = pick_route(s, ctx["transport"]);
            if route[0] == "" {
                continue;
            }
            r = route[1];
            out.append(Channel(
                id=cid, store=s.name, store_key=s.key, kind=kind, mode=route[0],
                travel_min=r.get("min", 0), shop_min=SHOP_MIN.get(kind, 20),
                walk_min=r.get("walk_min", 0), transfers=r.get("transfers", 0),
                transport_cost=r.get("cost", 0.0), windows=hours_windows(s.hours)
            ));
        }
    }
    return out;
}

"""Products for a need: its confirmed, non-disliked matches. A need with no match yet
falls back to catalog products of the same category; this does not change the graph."""
def products_for(item: InterestItem, cat: Catalog) -> list {
    if [item ->:Wants:->] {
        return usable_products(item);
    }
    return [prod for prod in [cat ->:Has:->][?:Product] if prod.category == need_key(item)];
}

"""Quotes for every plannable need. Expired offers are dropped. Offers without a price are
reported in notes, never priced at zero."""
def quotes_for(p: UserProfile, cat: Catalog, now: str = "") -> dict {
    quotes = [];
    notes = [];
    for item in items_of(p) {
        if not item.plannable() {
            continue;
        }
        for prod in products_for(item, cat) {
            for o in offers_of(prod) {
                if now != "" and not o.is_fresh(now) {
                    continue;
                }
                s = store_of(o);
                if o.price is None {
                    notes.append(f"{need_key(item)}: no price yet at {s.name} ({o.channel.lower()})");
                    continue;
                }
                discount = 0.0;
                if o.member_price is not None and o.member_program != "" {
                    discount = round(o.price - o.member_price, 2);
                }
                quotes.append(Quote(
                    need=need_key(item), channel=s.key + ":" + o.channel,
                    price=o.price, weight_kg=prod.weight_kg,
                    discount=discount, member_only=o.member_program,
                    stock=STOCK[o.availability.name], observed_at=o.observed_at, offer=o
                ));
            }
        }
    }
    return {"quotes": quotes, "notes": notes};
}
