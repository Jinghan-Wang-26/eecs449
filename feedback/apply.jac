"""Apply feedback along About edges, so a local issue updates only the item, offer, or match it concerns."""

import from models.profile { UserProfile }
import from models.interest { InterestItem, InterestKind, InterestStatus }
import from models.plan { PlanItem, ItemOutcome }
import from models.catalog { Availability }
import from models.events { FeedbackEvent, FeedbackReason }
import from models.graph { Has, About, event_log_of, need_of, offer_of, product_of, mark_disliked }

glob OUTCOME: dict = {
    "PURCHASED": ItemOutcome.PURCHASED,
    "BOUGHT_ELSEWHERE": ItemOutcome.CANCELLED,
    "OUT_OF_STOCK": ItemOutcome.UNAVAILABLE,
    "BUSY": ItemOutcome.POSTPONED,
    "HAVE_AT_HOME": ItemOutcome.POSTPONED
};

"""Record one feedback event and apply it. Returns False if event_id was already processed."""
def record_feedback(p: UserProfile, event_id: str, reason: FeedbackReason, about: list, text: str = "", at: str = "", until: str = "") -> bool {
    log = event_log_of(p);
    if event_id in log.seen {
        return False;
    }
    ev = FeedbackEvent(event_id=event_id, reason=reason, text=text, at=at, until=until);
    log +>:Has:+> ev;
    for n in about {
        ev +>:About:+> n;
        apply_to(ev, n);
    }
    log.seen = log.seen + [event_id];
    return True;
}

"""Targets are PlanItems or InterestItems."""
def apply_to(ev: FeedbackEvent, n: any) -> None {
    pi = n if isinstance(n, PlanItem) else None;
    need = need_of(pi) if pi is not None else (n if isinstance(n, InterestItem) else None);
    o = offer_of(pi) if pi is not None else None;
    r = ev.reason;
    if pi is not None and r.name in OUTCOME {
        pi.outcome = OUTCOME[r.name];
    }
    if r == FeedbackReason.PURCHASED or r == FeedbackReason.BOUGHT_ELSEWHERE {
        # Purchases update history, not interest. Replenish items stay active for the next cycle.
        if need is not None {
            need.last_purchased_at = ev.at;
            if need.kind == InterestKind.NEED {
                need.status = InterestStatus.ARCHIVED;
            }
        }
    } elif r == FeedbackReason.OUT_OF_STOCK {
        # An observation about this offer; the need and its priority are unchanged.
        if o is not None {
            o.availability = Availability.OUT;
            o.observed_at = ev.at;
            o.source = "user";
        }
    } elif r == FeedbackReason.HAVE_AT_HOME {
        if need is not None and ev.until != "" {
            need.snoozed_until = ev.until;
        }
    } elif r == FeedbackReason.DISLIKED {
        # Only this product stops matching; the category stays.
        if need is not None and o is not None {
            mark_disliked(need, product_of(o));
        }
    }
    # BUSY only reschedules. TOO_EXPENSIVE and INCONVENIENT change the current trip;
    # the planner asks before saving them as long-term preferences.
}
