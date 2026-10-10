"""Build in-store / delivery / mixed candidates and rank them (README "Compare Candidate Plans").

The search is bounded: every subset of at most MAX_CHANNELS channels, and every way to
assign each need to one quote inside that subset. Hard constraints are checked before scoring.
"""

import from itertools { combinations }
import from planning.types { Candidate, CostBreakdown }
import from planning.cost { basket_cost }
import from planning.constraints { check_constraints }

glob MAX_CHANNELS: int = 2,
     MAX_OPTIONS: int = 3,
     ORDER_MIN: int = 10,                  # active time to place a delivery order
     REF_COST: float = 100.0;              # used when the user has no budget

"""All combinations picking one element from each list."""
def cartesian(options: list) -> list {
    out = [[]];
    for choices in options {
        grown = [];
        for prefix in out {
            for c in choices {
                grown.append(prefix + [c]);
            }
        }
        out = grown;
    }
    return out;
}

def build_candidates(needs: list, channels: dict, quotes: list) -> list {
    usable = [q for q in quotes if q.stock != "NO" and q.channel in channels];
    ids = sorted(channels.keys());
    out = [];
    for k in range(1, MAX_CHANNELS + 1) {
        for subset in combinations(ids, k) {
            covered = [];
            options = [];
            unmet = [];
            for n in needs {
                qs = [q for q in usable if q.need == n.key and q.channel in subset];
                if qs {
                    covered.append(n.key);
                    options.append(qs);
                } else {
                    unmet.append(n.key);
                }
            }
            if not covered {
                continue;
            }
            for picks in cartesian(options) {
                used = sorted(set([q.channel for q in picks]));
                # an assignment that uses fewer channels was already built from a smaller subset
                if len(used) < k {
                    continue;
                }
                assignment = {};
                for i in range(len(picks)) {
                    assignment[covered[i]] = picks[i];
                }
                out.append(Candidate(
                    assignment=assignment, channels=used, unmet=list(unmet),
                    cost=CostBreakdown(subtotals={}, per_channel={}, notes=[]),
                    days={}, violations=[], warnings=[], labels=[]
                ));
            }
        }
    }
    return out;
}

def evaluate(c: Candidate, needs: dict, channels: dict, ctx: dict, memberships: list) -> None {
    c.cost = basket_cost(c.assignment, needs, channels, memberships);
    c.carried_kg = 0.0;
    c.active_min = 0;
    c.transfers = 0;
    c.unknowns = 0;
    trips = 0;
    for key in c.assignment {
        q = c.assignment[key];
        if channels[q.channel].kind != "DELIVERY" {
            c.carried_kg += q.weight_kg * needs[key].qty;
        }
        if q.stock == "UNKNOWN" {
            c.unknowns += 1;
        }
    }
    for cid in c.channels {
        ch = channels[cid];
        if ch.kind == "DELIVERY" {
            c.active_min += ORDER_MIN;
            if not ch.fee_known {
                c.unknowns += 1;
            }
        } else {
            c.active_min += ch.travel_min + ch.shop_min;
            c.transfers += ch.transfers;
            trips += 1;
        }
    }
    c.time_cost = round(c.active_min / 60.0 * ctx["time_value"], 2);
    check_constraints(c, ctx, channels);

    # every metric is mapped to 0..1 with fixed reference scales; weights sum to 1.
    # Time is priced at the user's time value, so it shares the money scale.
    w = ctx["weights"];
    ref_cost = ctx["budget"] if ctx["budget"] > 0 else REF_COST;
    limit = ctx["carry_limit_kg"] if ctx["carry_limit_kg"] > 0 else 1.0;
    cost_n = min(c.cost.total() / ref_cost, 1.0);
    time_n = min(c.time_cost / ref_cost, 1.0);
    effort_n = min(0.6 * c.carried_kg / limit + 0.2 * c.transfers + 0.2 * max(trips - 1, 0), 1.0);
    risk_n = min(c.unknowns / max(len(c.assignment), 1), 1.0);
    c.score = round(w["cost"] * cost_n + w["time"] * time_n + w["effort"] * effort_n + w["risk"] * risk_n, 4);
}

"""A plan is not recommended when a faster plan costs less once time is priced in:
the money it saves is less than the extra time is worth. The fastest plan always stays."""
def worth_the_time(plans: list) -> list {
    keep = [];
    for x in plans {
        beaten = [y for y in plans if y.active_min < x.active_min and y.effective_cost() < x.effective_cost()];
        if not beaten {
            keep.append(x);
        }
    }
    return keep;
}

"""Up to three distinct feasible plans. One plan can win several labels;
no option is invented to fill a slot."""
def select_options(cands: list) -> list {
    all_feasible = [c for c in cands if c.feasible()];
    if not all_feasible {
        return [];
    }
    feasible = worth_the_time(all_feasible);
    rankings = [
        ["BALANCED", sorted(feasible, key=lambda c: Candidate : (c.score, c.cost.total()))],
        ["COST_FIRST", sorted(feasible, key=lambda c: Candidate : (c.cost.total(), c.effective_cost()))],
        ["CONVENIENCE_FIRST", sorted(feasible, key=lambda c: Candidate : (c.active_min, c.carried_kg, c.cost.total()))]
    ];
    picks = [];
    for r in rankings {
        best = r[1][0];
        best.labels.append(r[0]);
        if best not in picks {
            picks.append(best);
        }
    }
    # say so when the cheapest plan overall was dropped by the time rule
    cheapest = sorted(all_feasible, key=lambda c: Candidate : (c.cost.total(), c.active_min))[0];
    cost_pick = [c for c in picks if "COST_FIRST" in c.labels][0];
    if cheapest not in feasible {
        saved = cost_pick.cost.total() - cheapest.cost.total();
        extra = cheapest.active_min - cost_pick.active_min;
        worth = cheapest.time_cost - cost_pick.time_cost;
        cost_pick.skipped = f"a plan ${saved:.2f} cheaper takes {extra} more min (~${worth:.2f} of your time), so it is not recommended";
    }
    return picks[:MAX_OPTIONS];
}

def describe(c: Candidate, channels: dict) -> str {
    parts = [];
    for cid in c.channels {
        ch = channels[cid];
        items = [k for k in c.assignment if c.assignment[k].channel == cid];
        parts.append(f"{ch.store} {ch.kind.lower()}: {', '.join(items)}");
    }
    total = f"${c.cost.total():.2f}";
    if c.cost.total_max() > c.cost.total() {
        total = f"${c.cost.total():.2f}-${c.cost.total_max():.2f}";
    }
    text = f"[{'/'.join(c.labels)}] {'; '.join(parts)} | {total} | {c.active_min} min (~${c.time_cost:.2f} of your time) | carry {c.carried_kg:.1f} kg";
    if c.warnings {
        text += " | note: " + "; ".join(c.warnings);
    }
    if c.skipped {
        text += " | " + c.skipped;
    }
    return text;
}

"""No feasible plan: say what is missing and why, without relaxing anything."""
def explain_infeasible(cands: list) -> str {
    if not cands {
        return "No store or delivery option carries any of these items.";
    }
    unmet = [];
    reasons = [];
    for c in cands {
        for u in c.unmet {
            if u not in unmet {
                unmet.append(u);
            }
        }
        for v in c.violations {
            if v not in reasons {
                reasons.append(v);
            }
        }
    }
    complete = [c for c in cands if not c.unmet];
    lines = ["No plan meets all your requirements."];
    if not complete and unmet {
        lines.append("Not available through any single plan: " + ", ".join(unmet) + ".");
    }
    if reasons {
        lines.append("What blocks the options:");
        for r in reasons[:5] {
            lines.append("- " + r);
        }
    }
    lines.append("You could change a package size, split into another trip, or postpone a non-urgent item.");
    return "\n".join(lines);
}
