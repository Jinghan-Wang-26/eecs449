"""Hard constraints. A violation removes a plan; a warning stays visible on it.
Unknown stock is never treated as confirmed, and unverified fees are never treated as zero."""

import from planning.types { Candidate, first_fit, day_index }

"""ctx comes from models.profile.effective_constraints."""
def check_constraints(c: Candidate, ctx: dict, channels: dict) -> None {
    c.violations = [];
    c.warnings = [];
    latest = -1;
    for cid in c.channels {
        ch = channels[cid];
        day = "";
        if ch.kind == "DELIVERY" {
            if not ch.covers_area {
                c.violations.append(f"{ch.store} does not deliver to your area");
            }
            sub = c.cost.subtotals.get(cid, 0.0);
            if sub < ch.min_order {
                c.violations.append(f"{ch.store} delivery needs a ${ch.min_order:.2f} minimum order; this basket is ${sub:.2f}");
            }
            # someone has to be home to receive it
            day = first_fit(ctx["free_windows"], ch.windows, 1, ch.ready_day);
            if day == "" {
                c.violations.append(f"no {ch.store} delivery window while you are home");
            }
        } else {
            if ch.mode and ch.mode not in ctx["transport"] {
                c.violations.append(f"the {ch.store} trip needs {ch.mode}, which is not in your transport for this trip");
            }
            if ch.walk_min > ctx["max_walk_min"] {
                c.violations.append(f"the {ch.store} trip walks {ch.walk_min} min, over your {ctx['max_walk_min']} min limit");
            }
            if ch.transfers > ctx["max_transfers"] {
                c.violations.append(f"the {ch.store} trip has {ch.transfers} transfers, over your limit of {ctx['max_transfers']}");
            }
            day = first_fit(ctx["free_windows"], ch.windows, ch.travel_min + ch.shop_min);
            if day == "" {
                c.violations.append(f"{ch.store} is not open long enough during your free time");
            }
        }
        if day != "" {
            c.days[cid] = day;
        }
        if day != "" and day_index(day) > latest {
            latest = day_index(day);
            c.ready_day = day;
        }
    }
    if ctx["deadline"] and c.ready_day and day_index(c.ready_day) > day_index(ctx["deadline"]) {
        c.violations.append(f"items arrive {c.ready_day}, after your {ctx['deadline']} deadline");
    }
    if c.carried_kg > ctx["carry_limit_kg"] {
        c.violations.append(f"you would carry {c.carried_kg:.1f} kg, over your {ctx['carry_limit_kg']:.1f} kg limit");
    }
    budget = ctx["budget"];
    if budget > 0 {
        if c.cost.total() > budget {
            c.violations.append(f"estimated ${c.cost.total():.2f} is over your ${budget:.2f} budget");
        } elif c.cost.total_max() > budget {
            c.warnings.append(f"may reach ${c.cost.total_max():.2f} if estimated fees are higher, over your ${budget:.2f} budget");
        }
    }
    for key in c.assignment {
        if c.assignment[key].stock == "UNKNOWN" {
            c.warnings.append(f"{key}: stock at {channels[c.assignment[key].channel].store} is not confirmed");
        }
    }
    for note in c.cost.notes {
        c.warnings.append(note);
    }
}
