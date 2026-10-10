"""Edges and graph helpers.

    root -> UserProfile -[Owns]-> InterestPool -[Has]-> InterestItem -[Wants]-> Product
                        -[Owns]-> TripConstraints
                        -[Owns]-> Catalog -[Has]-> Store / Product / Offer
                                  Offer -[ForProduct]-> Product,  Offer -[AtStore]-> Store
                        -[Owns]-> ShoppingPlan -[Contains]-> FulfillmentLeg -[AtStore]-> Store
                                                             -[Contains]-> PlanItem -[Satisfies]-> InterestItem
                                                                                    -[UsesOffer]-> Offer
                        -[Owns]-> EventLog -[Has]-> FeedbackEvent -[About]-> PlanItem / InterestItem / ...
                        -[Owns]-> Inbox    -[Has]-> Reminder      -[About]-> InterestItem / ShoppingPlan / Offer
"""

import from datetime { datetime }
import from models.profile { UserProfile, TripConstraints }
import from models.interest { InterestPool, InterestItem }
import from models.plan { ShoppingPlan, FulfillmentLeg, PlanItem }
import from models.catalog { Catalog, Product, Store, Offer }
import from models.events { EventLog, FeedbackEvent, Inbox, Reminder, ReminderStatus }

edge Owns {}
edge Has {}
edge Contains {}
edge Satisfies {}
edge ForProduct {}
edge AtStore {}
edge About {}

"""A need's match to a product. Substitutes need confirmation; dislikes stay local to this pair."""
edge Wants {
    has substitute: bool = False,
        confirmed: bool = True,
        disliked: bool = False;
}

"""Offer values at planning time. Comparing them with the live Offer shows what changed."""
edge UsesOffer {
    has price_at_plan: float | None = None,
        availability_at_plan: str = "",
        observed_at: str = "";
}

"""Each jac start user has their own root, so one profile per root."""
def profile_of(r: any) -> UserProfile {
    found = [r -->][?:UserProfile];
    if found {
        return found[0];
    }
    p = UserProfile();
    r ++> p;
    p +>:Owns:+> InterestPool();
    return p;
}

"""The profile's single child of this type, created on first use."""
def owned(p: UserProfile, kind: type) -> any {
    for n in [p ->:Owns:->] {
        if isinstance(n, kind) {
            return n;
        }
    }
    n = kind();
    p +>:Owns:+> n;
    return n;
}

def pool_of(p: UserProfile) -> InterestPool {
    return [p ->:Owns:->][?:InterestPool][0];
}

def catalog_of(p: UserProfile) -> Catalog {
    return owned(p, Catalog);
}

def event_log_of(p: UserProfile) -> EventLog {
    return owned(p, EventLog);
}

def inbox_of(p: UserProfile) -> Inbox {
    return owned(p, Inbox);
}

def items_of(p: UserProfile) -> list {
    return [pool_of(p) ->:Has:->][?:InterestItem];
}

def trip_of(p: UserProfile) -> TripConstraints | None {
    found = [p ->:Owns:->][?:TripConstraints];
    return found[0] if found else None;
}

def plans_of(p: UserProfile) -> list {
    return [p ->:Owns:->][?:ShoppingPlan];
}

def add_need(p: UserProfile, spec: dict) -> InterestItem {
    item = InterestItem(product_spec=spec);
    pool_of(p) +>:Has:+> item;
    return item;
}

def assign(n: any, fields: dict) -> None {
    for k in fields {
        setattr(n, k, fields[k]);
    }
}

# ---- catalog ----

def find_in(cat: Catalog, kind: type, key: str) -> any {
    for n in [cat ->:Has:->] {
        if isinstance(n, kind) and n.key == key {
            return n;
        }
    }
    return None;
}

def upsert_store(cat: Catalog, key: str, fields: dict = {}) -> Store {
    s = find_in(cat, Store, key);
    if s is None {
        s = Store(key=key);
        cat +>:Has:+> s;
    }
    assign(s, fields);
    return s;
}

def upsert_product(cat: Catalog, key: str, fields: dict = {}) -> Product {
    prod = find_in(cat, Product, key);
    if prod is None {
        prod = Product(key=key);
        cat +>:Has:+> prod;
    }
    assign(prod, fields);
    return prod;
}

"""One Offer per store, product, and channel; a refresh updates it in place."""
def upsert_offer(cat: Catalog, s: Store, prod: Product, channel: str, fields: dict = {}) -> Offer {
    key = s.key + ":" + prod.key + ":" + channel;
    o = find_in(cat, Offer, key);
    if o is None {
        o = Offer(key=key, channel=channel);
        cat +>:Has:+> o;
        o +>:ForProduct:+> prod;
        o +>:AtStore:+> s;
    }
    assign(o, fields);
    return o;
}

def product_of(o: Offer) -> Product {
    return [o ->:ForProduct:->][?:Product][0];
}

"""Store of an Offer or a FulfillmentLeg. A leg from a delivery-only provider still has one."""
def store_of(n: any) -> Store | None {
    found = [n ->:AtStore:->][?:Store];
    return found[0] if found else None;
}

def offers_of(prod: Product) -> list {
    return [prod <-:ForProduct:<-][?:Offer];
}

# ---- needs to products ----

def want(need: InterestItem, prod: Product, substitute: bool = False, confirmed: bool = True) -> None {
    found = [edge need ->:Wants:-> prod];
    if found {
        found[0].substitute = substitute;
        found[0].confirmed = confirmed;
        return;
    }
    need +>:Wants(substitute=substitute, confirmed=confirmed):+> prod;
}

def mark_disliked(need: InterestItem, prod: Product) -> bool {
    found = [edge need ->:Wants:-> prod];
    if not found {
        return False;
    }
    found[0].disliked = True;
    return True;
}

"""Products planning may use for this need: not disliked, and substitutes only once confirmed."""
def usable_products(need: InterestItem) -> list {
    return [need ->:Wants:confirmed==True, disliked==False:->][?:Product];
}

"""Offers for a need's usable products. Pass now to drop expired ones; stockouts stay so planning can explain them."""
def offers_for(need: InterestItem, now: str = "") -> list {
    out: list = [];
    for prod in usable_products(need) {
        for o in offers_of(prod) {
            if now == "" or o.is_fresh(now) {
                out.append(o);
            }
        }
    }
    return out;
}

# ---- plans ----

def add_leg(plan: ShoppingPlan, s: Store | None, channel: str, fields: dict = {}) -> FulfillmentLeg {
    leg = FulfillmentLeg(channel=channel);
    assign(leg, fields);
    plan +>:Contains:+> leg;
    if s is not None {
        leg +>:AtStore:+> s;
    }
    return leg;
}

def legs_of(plan: ShoppingPlan) -> list {
    return [plan ->:Contains:->][?:FulfillmentLeg];
}

"""A PlanItem points back to the need it covers, so outcomes can flow back to the pool."""
def add_plan_item(leg: FulfillmentLeg, need: InterestItem, o: Offer | None = None, price: float | None = None) -> PlanItem {
    pi = PlanItem(name=need.product_spec.get("type", ""), qty=need.product_spec.get("qty", 1));
    leg +>:Contains:+> pi;
    pi +>:Satisfies:+> need;
    if o is not None {
        use_offer(pi, o, price if price is not None else o.price);
    }
    return pi;
}

"""Link an item to its offer with a snapshot. price is what the planner chose, e.g. a member price."""
def use_offer(pi: PlanItem, o: Offer, price: float | None) -> None {
    pi +>:UsesOffer(price_at_plan=price, availability_at_plan=o.availability.name, observed_at=o.observed_at):+> o;
}

def items_of_leg(leg: FulfillmentLeg) -> list {
    return [leg ->:Contains:->][?:PlanItem];
}

def plan_items_of(plan: ShoppingPlan) -> list {
    out: list = [];
    for leg in legs_of(plan) {
        out.extend(items_of_leg(leg));
    }
    return out;
}

def leg_of(pi: PlanItem) -> FulfillmentLeg {
    return [pi <-:Contains:<-][?:FulfillmentLeg][0];
}

def need_of(pi: PlanItem) -> InterestItem {
    return [pi ->:Satisfies:->][?:InterestItem][0];
}

def offer_of(pi: PlanItem) -> Offer | None {
    found = [pi ->:UsesOffer:->][?:Offer];
    return found[0] if found else None;
}

"""Weight the user carries home: every in-store and pickup leg together, as one trip."""
def carried_kg(plan: ShoppingPlan) -> float {
    total = 0.0;
    for leg in legs_of(plan) {
        if not leg.carried() {
            continue;
        }
        for pi in items_of_leg(leg) {
            o = offer_of(pi);
            if o is not None {
                total += product_of(o).weight_kg * pi.qty;
            }
        }
    }
    return total;
}

"""Merchandise subtotal from planning-time prices. Unknown prices are listed, never counted as zero."""
def merchandise(plan: ShoppingPlan) -> dict {
    subtotal = 0.0;
    unknown: list = [];
    for pi in plan_items_of(plan) {
        uses = [edge pi ->:UsesOffer:->];
        if not uses or uses[0].price_at_plan is None {
            unknown.append(pi.name);
            continue;
        }
        subtotal += uses[0].price_at_plan * pi.qty;
    }
    return {"subtotal": round(subtotal, 2), "unknown": unknown};
}

"""Differences between each item's snapshot and its live Offer. Non-empty means an accepted plan needs review."""
def plan_changes(plan: ShoppingPlan, now: str = "", memberships: list[str] = []) -> list {
    changes: list = [];
    for pi in plan_items_of(plan) {
        uses = [edge pi ->:UsesOffer:->];
        o = offer_of(pi);
        if not uses or o is None {
            continue;
        }
        snap = uses[0];
        price = o.price_for(memberships);
        if price != snap.price_at_plan {
            changes.append({"item": pi.name, "field": "price", "before": snap.price_at_plan, "after": price});
        }
        if o.availability.name != snap.availability_at_plan {
            changes.append({"item": pi.name, "field": "availability", "before": snap.availability_at_plan, "after": o.availability.name});
        }
        if now != "" and not o.is_fresh(now) {
            changes.append({"item": pi.name, "field": "stale", "before": o.observed_at, "after": o.valid_until});
        }
    }
    return changes;
}

# ---- feedback and reminders ----

def about_of(n: any) -> list {
    return [n ->:About:->];
}

"""Feedback history of a need, plan item, product, or store."""
def feedback_of(n: any) -> list {
    return [n <-:About:<-][?:FeedbackEvent];
}

def reminders_of(p: UserProfile) -> list {
    return [inbox_of(p) ->:Has:->][?:Reminder];
}

def hours_between(a: str, b: str) -> float {
    if a == "" or b == "" {
        return 1e9;
    }
    return (datetime.fromisoformat(b) - datetime.fromisoformat(a)).total_seconds() / 3600;
}

"""Create a reminder unless one with the same key is still open, was dismissed, or fired within the cooldown."""
def add_reminder(p: UserProfile, dedup_key: str, kind: str, message: str, fire_at: str, about: list, now: str, cooldown_h: int = 24) -> Reminder | None {
    for r in reminders_of(p) {
        if r.dedup_key != dedup_key {
            continue;
        }
        if r.status == ReminderStatus.PENDING or r.status == ReminderStatus.SNOOZED or r.status == ReminderStatus.DISMISSED {
            return None;
        }
        if hours_between(r.created_at, now) < cooldown_h {
            return None;
        }
    }
    r = Reminder(dedup_key=dedup_key, kind=kind, message=message, fire_at=fire_at, created_at=now);
    inbox_of(p) +>:Has:+> r;
    for n in about {
        r +>:About:+> n;
    }
    return r;
}

"""Pending or snoozed reminders whose time has come."""
def due_reminders(p: UserProfile, now: str) -> list {
    return [r for r in reminders_of(p)
        if (r.status == ReminderStatus.PENDING or r.status == ReminderStatus.SNOOZED) and r.fire_at <= now];
}
