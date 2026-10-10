"""Total basket cost (README "Calculate Total Basket Cost"):

    merchandise - eligible discounts + taxes + delivery/service fees + tips + transportation
"""

import from planning.types { CostBreakdown }

"""assignment: need key -> Quote. needs: key -> Need. channels: id -> Channel."""
def basket_cost(assignment: dict, needs: dict, channels: dict, memberships: list) -> CostBreakdown {
    cb = CostBreakdown(subtotals={}, per_channel={}, notes=[]);
    for key in assignment {
        q = assignment[key];
        qty = needs[key].qty;
        line = q.price * qty;
        disc = 0.0;
        if q.discount > 0 {
            if q.member_only == "" or q.member_only in memberships {
                disc = q.discount * qty;
            } else {
                cb.notes.append(f"{key}: {q.member_only} price not applied (no membership)");
            }
        }
        cb.merchandise += line;
        cb.discounts += disc;
        cb.subtotals[q.channel] = cb.subtotals.get(q.channel, 0.0) + line - disc;
    }
    for cid in cb.subtotals {
        ch = channels[cid];
        sub = cb.subtotals[cid];
        leg = {"tax": sub * ch.tax_rate, "delivery": 0.0, "service": 0.0, "tip": 0.0, "transport": 0.0};
        if ch.kind == "DELIVERY" {
            leg["delivery"] = ch.delivery_fee;
            if ch.free_over > 0 and sub >= ch.free_over {
                leg["delivery"] = 0.0;
            }
            if not ch.fee_known {
                cb.unverified_max += max(ch.fee_max - leg["delivery"], 0.0);
                cb.notes.append(f"{ch.store} delivery fee is an estimate");
            }
            leg["service"] = sub * ch.service_fee_pct;
            leg["tip"] = ch.tip;
        } else {
            leg["transport"] = ch.transport_cost;
        }
        cb.tax += leg["tax"];
        cb.delivery_fees += leg["delivery"];
        cb.service_fees += leg["service"];
        cb.tips += leg["tip"];
        cb.transport += leg["transport"];
        cb.per_channel[cid] = {k: round(leg[k], 2) for k in leg};
    }
    return cb;
}
