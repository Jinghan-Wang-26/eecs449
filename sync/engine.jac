"""Validate a batch, apply external events once, then reconcile plans once.

Generated plans/reminders are outputs, never input events. Receipts live on the
user's graph so replaying a request after reconnecting does not apply it twice.
"""

import json;
import math;
import from app_settings { get_settings, stamp, instant }
import from models.profile { UserProfile, TripConstraints }
import from models.plan { PlanStatus, ItemOutcome }
import from models.catalog { Offer, Availability }
import from models.events { SyncState, FeedbackReason }
import from models.graph { owned, catalog_of, find_in, items_of, plans_of, plan_items_of, need_of, plan_changes, add_reminder, product_of }
import from feedback.apply { record_feedback }
import from planning.lifecycle { plan_shopping }
import from notify.reminders { check_reminders, offer_snapshot }

def targets(p: UserProfile, key: str) -> list {
    needs = [n for n in items_of(p) if n.product_spec.get("type") == key and n.kind.name != "DISCOVER" and n.status.name != "ARCHIVED"];
    if len(needs) != 1 { raise ValueError("Feedback needs exactly one active interest: " + key); }
    out = [needs[0]];
    for plan in plans_of(p) {
        if plan.status in [PlanStatus.ACCEPTED, PlanStatus.IN_PROGRESS] {
            for pi in plan_items_of(plan) {
                if need_of(pi) == needs[0] { out.append(pi); }
            }
        }
    }
    return out;
}

def validate_event(p: UserProfile, e: dict, now: str) -> None {
    if not isinstance(e.get("id"), str) or e["id"].strip() == "" {
        raise ValueError("Each event needs a nonempty string id");
    }
    if e.get("type") == "offer" {
        o = find_in(catalog_of(p), Offer, e.get("key", ""));
        if o is None { raise ValueError("Unknown offer"); }
        fields = e.get("fields", {});
        if not isinstance(fields, dict) or not fields or not all([k in ["price", "member_price", "availability", "observed_at", "valid_until"] for k in fields]) {
            raise ValueError("Unsupported offer update fields");
        }
        for k in ["price", "member_price"] {
            value = fields.get(k);
            if value is not None and (type(value) not in [int, float] or not math.isfinite(value) or value < 0) {
                raise ValueError("Prices must be nonnegative finite numbers or null");
            }
        }
        if "availability" in fields and fields["availability"] not in ["IN_STOCK", "LOW", "OUT", "UNKNOWN"] {
            raise ValueError("Invalid availability");
        }
        observed = fields.get("observed_at", "");
        valid = fields.get("valid_until", "");
        if observed == "" or valid == "" or instant(observed) > instant(now) or instant(valid) < instant(observed) {
            raise ValueError("Offer updates require observation and expiry timestamps, with no future observation");
        }
    } elif e.get("type") == "feedback" {
        if e.get("reason") not in ["PURCHASED", "BOUGHT_ELSEWHERE", "OUT_OF_STOCK", "BUSY", "HAVE_AT_HOME", "DISLIKED", "TOO_EXPENSIVE", "INCONVENIENT"] {
            raise ValueError("Invalid feedback reason");
        }
        about = targets(p, e.get("target", ""));
        if e["reason"] in ["OUT_OF_STOCK", "DISLIKED"] and len(about) == 1 {
            raise ValueError("This reason needs an accepted plan item to identify the specific offer/product");
        }
        if e.get("until", "") != "" and instant(e["until"]) <= instant(now) {
            raise ValueError("Snooze time must be in the future");
        }
        if e["reason"] in ["BUSY", "HAVE_AT_HOME"] and not e.get("until") {
            raise ValueError("This feedback requires an explicit until timestamp");
        }
        trip = e.get("trip", {});
        if not isinstance(trip, dict) or any([k not in ["budget", "transport"] for k in trip]) {
            raise ValueError("Only explicit trip budget and transport overrides are supported");
        }
        if "budget" in trip and (type(trip["budget"]) not in [int, float] or not math.isfinite(trip["budget"]) or trip["budget"] < 0) {
            raise ValueError("Trip budget must be nonnegative and finite");
        }
        if "transport" in trip and (not isinstance(trip["transport"], list) or not trip["transport"] or any([m not in ["WALK", "BUS", "CAR", "BIKE", "RIDESHARE"] for m in trip["transport"]])) {
            raise ValueError("Invalid trip transport");
        }
    } else {
        raise ValueError("Event type must be offer or feedback");
    }
}

def material_changes(plan: any, now: str, p: UserProfile, cfg: dict) -> list {
    out = [];
    for change in plan_changes(plan, now, p.memberships) {
        if change["field"] != "price" or change["before"] is None or change["after"] is None or abs(change["before"] - change["after"]) >= cfg["material_price_change"] {
            out.append(change);
        }
    }
    return out;
}

def sync_events(p: UserProfile, events: list, now: str, settings: dict = {}) -> dict {
    cfg = get_settings(settings);
    if p.data_mode != "" { cfg["data_mode"] = p.data_mode; }
    now = stamp(now, cfg);
    state = owned(p, SyncState);
    if state.syncing { raise ValueError("A synchronization is already in progress"); }
    pending = [];
    resolved = {};
    receipts = dict(state.receipts);
    for e in events {
        if not isinstance(e, dict) { raise ValueError("Events must be objects"); }
        payload = json.dumps(e, sort_keys=True);
        key = e.get("id", "");
        if not isinstance(key, str) { raise ValueError("Event id must be a string"); }
        if key in receipts {
            if receipts[key] != payload { raise ValueError("An event id cannot be reused with a different payload"); }
            continue;
        }
        validate_event(p, e, now);
        if e["type"] == "feedback" { resolved[e["id"]] = targets(p, e["target"]); }
        pending.append(e);
        receipts[key] = payload;
    }
    state.syncing = True;
    try {
        if not state.observations { state.observations = offer_snapshot(p, now); }
        changed = False;
        feedback_changed = False;
        recommendation_changed = False;
        affected = [];
        for e in pending {
            if e["type"] == "offer" {
                o = find_in(catalog_of(p), Offer, e["key"]);
                fields = e["fields"];
                # Out-of-order provider responses never overwrite newer user observations.
                if o.observed_at != "" and instant(fields["observed_at"]) < instant(o.observed_at) { continue; }
                relevant = any([n.plannable() and n.product_spec.get("type") == product_of(o).category for n in items_of(p)]);
                for k in fields {
                    value = Availability[fields[k]] if k == "availability" else fields[k];
                    if getattr(o, k) != value {
                        changed = True;
                        if relevant and (k == "availability" or (k in ["price", "member_price"] and (getattr(o, k) is None or value is None or abs(getattr(o, k) - value) >= cfg["material_price_change"]))) {
                            recommendation_changed = True;
                        }
                    }
                    setattr(o, k, value);
                }
                o.source = "kroger" if cfg["data_mode"] == "live" else "mock";
            } else {
                # Resolve targets before applying (a purchase archives a NEED).
                about = resolved[e["id"]];
                applied = record_feedback(p, e["id"], FeedbackReason[e["reason"]], about,
                                          text=e.get("text", ""), at=now, until=e.get("until", ""));
                if applied {
                    changed = True;
                    feedback_changed = True;
                    trip = owned(p, TripConstraints);
                    for k in e.get("trip", {}) { setattr(trip, k, e["trip"][k]); }
                    if e["reason"] in ["TOO_EXPENSIVE", "INCONVENIENT"] and not e.get("trip") {
                        trip.notes = "Please confirm a trip budget or transport change before replanning preferences.";
                    }
                    for plan in plans_of(p) {
                        if plan.status in [PlanStatus.ACCEPTED, PlanStatus.IN_PROGRESS] {
                            pis = plan_items_of(plan);
                            if (e.get("trip") or e["reason"] in ["BUSY", "HAVE_AT_HOME", "DISLIKED", "TOO_EXPENSIVE", "INCONVENIENT"]) and any([pi in about for pi in pis]) {
                                if plan not in affected { affected.append(plan); }
                            }
                            if any([pi in about and pi.outcome != ItemOutcome.PENDING for pi in pis]) {
                                if plan.status == PlanStatus.ACCEPTED { plan.move_to(PlanStatus.IN_PROGRESS); }
                                if all([pi.outcome != ItemOutcome.PENDING for pi in pis]) { plan.move_to(PlanStatus.COMPLETED); }
                            }
                        }
                    }
                }
            }
        }
        # Receipts are committed after all validated input mutations.
        state.receipts = receipts;
        replan = False;
        reviewed = 0;
        for plan in plans_of(p) {
            changes = material_changes(plan, now, p, cfg);
            if plan in affected {
                changes.append({"item": "trip", "field": "feedback", "before": "accepted conditions", "after": "user requested a change"});
            }
            if plan.status in [PlanStatus.DRAFT, PlanStatus.PROPOSED] and (changes or feedback_changed or recommendation_changed) {
                replan = True;
            } elif plan.status in [PlanStatus.ACCEPTED, PlanStatus.IN_PROGRESS] and changes {
                plan.move_to(PlanStatus.NEEDS_REVIEW);
                summary = "; ".join([f"{c['item']} {c['field']}: {c['before']} -> {c['after']}" for c in changes]);
                plan.explanation += "\nNeeds review: " + summary;
                add_reminder(p, "plan-change:" + plan.created_at + ":" + plan.strategy.name + ":" + summary,
                             "PLAN_CHANGE", summary, now, [plan], now, cfg["reminder_cooldown_hours"]);
                reviewed += 1;
            }
        }
        result = {"plans": [], "message": ""};
        if replan {
            # Invalidate stale proposals even if no feasible replacement exists.
            for plan in plans_of(p) {
                if plan.status in [PlanStatus.DRAFT, PlanStatus.PROPOSED] { plan.move_to(PlanStatus.CANCELLED); }
            }
            result = plan_shopping(p, now, cfg);
            state.replan_count += 1;
        }
        reminders = check_reminders(p, now, cfg);
        return {"applied": len(pending), "changed": changed, "replanned": replan, "reviewed": reviewed,
                "message": result["message"], "new_reminders": len(reminders)};
    } finally {
        state.syncing = False;
    }
}
