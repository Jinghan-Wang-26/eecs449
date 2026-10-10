"""Edges and graph helpers.

    root -> UserProfile -[Owns]-> InterestPool -[Has]-> InterestItem
                        -[Owns]-> TripConstraints
                        -[Owns]-> ShoppingPlan -[Contains]-> PlanItem -[Satisfies]-> InterestItem
"""

import from models.profile { UserProfile, TripConstraints }
import from models.interest { InterestPool, InterestItem }
import from models.plan { ShoppingPlan, PlanItem }

edge Owns {}
edge Has {}
edge Contains {}
edge Satisfies {}

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

def pool_of(p: UserProfile) -> InterestPool {
    return [p ->:Owns:->][?:InterestPool][0];
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

"""A PlanItem points back to the need it covers, so outcomes can flow back to the pool."""
def add_plan_item(plan: ShoppingPlan, need: InterestItem, channel: str) -> PlanItem {
    pi = PlanItem(name=need.product_spec.get("type", ""), qty=need.product_spec.get("qty", 1), channel=channel);
    plan +>:Contains:+> pi;
    pi +>:Satisfies:+> need;
    return pi;
}

def need_of(pi: PlanItem) -> InterestItem {
    return [pi ->:Satisfies:->][?:InterestItem][0];
}
