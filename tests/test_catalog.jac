import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.plan { ShoppingPlan }
import from models.catalog { Catalog, Offer, Product, Store, Availability }
import from models.graph {
    Owns, Has, add_need, catalog_of, find_in, want, mark_disliked, usable_products, offers_for,
    product_of, store_of, add_leg, add_plan_item, carried_kg, merchandise, plan_changes
}
import from providers.mock { load_mock }

"""A profile off root, so tests do not share state."""
def fresh() -> UserProfile {
    p = UserProfile();
    p +>:Owns:+> InterestPool();
    return p;
}

def loaded() -> tuple {
    p = fresh();
    cat = catalog_of(p);
    load_mock(cat);
    return (p, cat);
}

def offer(cat: Catalog, key: str) -> Offer {
    return find_in(cat, Offer, key);
}

def product(cat: Catalog, key: str) -> Product {
    return find_in(cat, Product, key);
}

test "mock catalog loads and reloads in place" {
    p = fresh();
    cat = catalog_of(p);
    assert load_mock(cat) == 30;
    load_mock(cat);
    assert len([cat ->:Has:->][?:Offer]) == 30 and len([cat ->:Has:->][?:Store]) == 4;
    o = offer(cat, "bulk:rice-jasmine-20lb:IN_STORE");
    assert store_of(o).name == "Arbor Bulk Club" and product_of(o).weight_kg == 9.1;
    assert offer(cat, "quick:rice-jasmine-5lb:DELIVERY").price is None;
}

test "one need sees offers from several stores" {
    (p, cat) = loaded();
    milk = add_need(p, {"type": "milk", "qty": 1});
    want(milk, product(cat, "milk-whole-1gal"));
    stores = {store_of(o).key for o in offers_for(milk)};
    assert stores == {"huron", "corner", "quick"};
    assert len(offers_for(milk)) == 4;
    assert offers_for(milk, now="2026-10-20T00:00") == [];
}

test "substitutes need confirmation and dislikes stay local" {
    (p, cat) = loaded();
    yogurt = add_need(p, {"type": "yogurt", "qty": 1});
    plain = product(cat, "yogurt-plain-32oz");
    honey = product(cat, "yogurt-honey-32oz");
    want(yogurt, plain);
    want(yogurt, honey, substitute=True, confirmed=False);
    assert usable_products(yogurt) == [plain];
    want(yogurt, honey, substitute=True, confirmed=True);
    assert len(usable_products(yogurt)) == 2;
    assert mark_disliked(yogurt, plain);
    assert usable_products(yogurt) == [honey];
}

test "carried weight counts only in-store and pickup legs" {
    (p, cat) = loaded();
    plan = ShoppingPlan();
    p +>:Owns:+> plan;
    milk = add_need(p, {"type": "milk", "qty": 1});
    rice = add_need(p, {"type": "rice", "qty": 1});
    soap = add_need(p, {"type": "laundry detergent", "qty": 1});
    store_leg = add_leg(plan, find_in(cat, Store, "huron"), "IN_STORE", {"travel_min": 30, "transport_cost": 3.0});
    add_plan_item(store_leg, milk, offer(cat, "huron:milk-whole-1gal:IN_STORE"));
    add_plan_item(store_leg, rice, offer(cat, "huron:rice-jasmine-5lb:IN_STORE"));
    ship_leg = add_leg(plan, find_in(cat, Store, "bulk"), "DELIVERY");
    add_plan_item(ship_leg, soap, offer(cat, "bulk:detergent-92oz:DELIVERY"));
    assert abs(carried_kg(plan) - 6.2) < 1e-9;
    assert carried_kg(plan) > p.carry_limit_kg;
    assert store_of(ship_leg).key == "bulk";
}

test "unknown prices are listed, not counted as zero" {
    (p, cat) = loaded();
    plan = ShoppingPlan();
    leg = add_leg(plan, find_in(cat, Store, "quick"), "DELIVERY");
    add_plan_item(leg, add_need(p, {"type": "milk", "qty": 2}), offer(cat, "quick:milk-whole-1gal:DELIVERY"));
    add_plan_item(leg, add_need(p, {"type": "rice", "qty": 1}), offer(cat, "quick:rice-jasmine-5lb:DELIVERY"));
    m = merchandise(plan);
    assert m["subtotal"] == 9.98 and m["unknown"] == ["rice"];
}

test "plan_changes compares snapshots with live offers" {
    (p, cat) = loaded();
    plan = ShoppingPlan();
    leg = add_leg(plan, find_in(cat, Store, "bulk"), "IN_STORE");
    rice_offer = offer(cat, "bulk:rice-jasmine-20lb:IN_STORE");
    add_plan_item(leg, add_need(p, {"type": "rice", "qty": 1}), rice_offer, price=rice_offer.price_for(["ARBOR_CLUB"]));
    soap_offer = offer(cat, "bulk:detergent-92oz:IN_STORE");
    add_plan_item(leg, add_need(p, {"type": "laundry detergent", "qty": 1}), soap_offer, price=soap_offer.price_for(["ARBOR_CLUB"]));
    assert plan_changes(plan, now="2026-10-11T10:00", memberships=["ARBOR_CLUB"]) == [];
    soap_offer.member_price = 9.99;
    soap_offer.availability = Availability.OUT;
    changes = plan_changes(plan, memberships=["ARBOR_CLUB"]);
    assert [c["field"] for c in changes] == ["price", "availability"];
    assert changes[0]["before"] == 9.49 and changes[0]["after"] == 9.99;
    assert len(plan_changes(plan)) == 3;           # without the membership, both list prices differ from the member-price snapshots
    assert [c["field"] for c in plan_changes(plan, now="2026-10-18T00:00", memberships=["ARBOR_CLUB"])].count("stale") == 2;
}
