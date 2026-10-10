"""Plan lifecycle on top of the PlanStatus transition table in models/plan.jac.

    DRAFT -> PROPOSED -> ACCEPTED -> IN_PROGRESS -> COMPLETED
    any open state -> CANCELLED;  ACCEPTED / IN_PROGRESS -> NEEDS_REVIEW on a material change
"""

import from models.profile { UserProfile, effective_constraints }
import from models.plan { ShoppingPlan, PlanStatus, PlanStrategy, ItemOutcome }
import from models.catalog { Store }
import from models.events { FeedbackReason }
import from models.graph {
    Owns, catalog_of, items_of, plans_of, trip_of, find_in,
    add_leg, add_plan_item, plan_items_of, plan_changes
}
import from feedback.apply { record_feedback }
import from planning.inputs { need_key, needs_from_pool, channels_for, quotes_for }
import from planning.candidates { build_candidates, evaluate, select_options, describe, explain_infeasible }

"""Needs in the pool + the user's catalog -> up to three PROPOSED plans.
Older DRAFT / PROPOSED plans are replaced; accepted plans are left alone."""
def plan_shopping(p: UserProfile, now: str = "") -> dict {
    ctx = effective_constraints(p, trip_of(p));
    needs = needs_from_pool(p);
    if not needs {
        return {"plans": [], "message": "Your shopping list is empty."};
    }
    cat = catalog_of(p);
    channels = channels_for(cat, ctx);
    found = quotes_for(p, cat, now);
    by_key = {};
    for n in needs {
        by_key[n.key] = n;
    }
    by_id = {};
    for ch in channels {
        by_id[ch.id] = ch;
    }
    cands = build_candidates(needs, by_id, found["quotes"]);
    for c in cands {
        evaluate(c, by_key, by_id, ctx, p.memberships);
    }
    options = select_options(cands);
    if not options {
        msg = explain_infeasible(cands);
        if found["notes"] {
            msg += "\nAlso: " + "; ".join(found["notes"]);
        }
        return {"plans": [], "message": msg};
    }
    for old in plans_of(p) {
        if old.status == PlanStatus.DRAFT or old.status == PlanStatus.PROPOSED {
            old.move_to(PlanStatus.CANCELLED);
        }
    }
    items = {};
    for item in items_of(p) {
        if item.plannable() {
            items[need_key(item)] = item;
        }
    }
    plans = [];
    lines = [];
    for c in options {
        plans.append(save_plan(p, c, by_id, items, now));
        lines.append(plans[-1].explanation);
    }
    return {"plans": plans, "message": "\n".join(lines)};
}

"""One leg per channel, one item per need; each item snapshots the price it was planned at."""
def save_plan(p: UserProfile, c: any, channels: dict, items: dict, now: str) -> ShoppingPlan {
    cost = c.cost.as_dict();
    cost["time_cost"] = c.time_cost;
    cost["effective_total"] = c.effective_cost();
    plan = ShoppingPlan(
        strategy=PlanStrategy[c.labels[0]],
        cost=cost,
        total=c.cost.total(),
        active_min=c.active_min,
        carried_kg=round(c.carried_kg, 2),
        unmet=list(c.unmet),
        explanation=describe(c, channels),
        created_at=now
    );
    p +>:Owns:+> plan;
    cat = catalog_of(p);
    for cid in c.channels {
        ch = channels[cid];
        leg = add_leg(plan, find_in(cat, Store, ch.store_key), ch.kind, {
            "window": c.days.get(cid, ""),
            "travel_min": ch.travel_min,
            "shop_min": ch.shop_min,
            "transport_cost": ch.transport_cost,
            "fees": c.cost.per_channel.get(cid, {})
        });
        for key in c.assignment {
            q = c.assignment[key];
            if q.channel == cid {
                add_plan_item(leg, items[key], q.offer, q.offer.price_for(p.memberships));
            }
        }
    }
    plan.move_to(PlanStatus.PROPOSED);
    return plan;
}

"""Accepting one plan cancels the other proposals."""
def accept(p: UserProfile, plan: ShoppingPlan) -> bool {
    if not plan.move_to(PlanStatus.ACCEPTED) {
        return False;
    }
    for other in plans_of(p) {
        if other != plan and other.status == PlanStatus.PROPOSED {
            other.move_to(PlanStatus.CANCELLED);
        }
    }
    return True;
}

"""Record what happened to one item. feedback/apply updates the item and its need
(idempotent by event_id); this keeps the plan's state in step. The plan completes once
nothing is pending, even if some items failed."""
def record_outcome(p: UserProfile, plan: ShoppingPlan, name: str, reason: FeedbackReason, event_id: str, at: str = "") -> bool {
    if plan.status == PlanStatus.ACCEPTED {
        plan.move_to(PlanStatus.IN_PROGRESS);
    }
    if plan.status != PlanStatus.IN_PROGRESS {
        return False;
    }
    found = [pi for pi in plan_items_of(plan) if pi.name == name];
    if not found {
        return False;
    }
    applied = record_feedback(p, event_id, reason, [found[0]], at=at);
    if not [x for x in plan_items_of(plan) if x.outcome == ItemOutcome.PENDING] {
        plan.move_to(PlanStatus.COMPLETED);
    }
    return applied;
}

"""Compare the plan with live offers. A proposal is just rebuilt; an accepted or
in-progress plan goes to NEEDS_REVIEW with the differences listed."""
def review_changes(p: UserProfile, plan: ShoppingPlan, now: str = "") -> dict {
    changes = plan_changes(plan, now, p.memberships);
    if not changes {
        return {"action": "none", "changes": []};
    }
    if plan.status == PlanStatus.DRAFT or plan.status == PlanStatus.PROPOSED {
        return {"action": "replan", "changes": changes};
    }
    if plan.move_to(PlanStatus.NEEDS_REVIEW) {
        lines = [f"{ch['item']} {ch['field']}: {ch['before']} -> {ch['after']}" for ch in changes];
        plan.explanation += "\nNeeds review: " + "; ".join(lines);
        return {"action": "review", "changes": changes};
    }
    return {"action": "none", "changes": changes};
}
