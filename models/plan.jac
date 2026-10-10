"""ShoppingPlan, FulfillmentLeg, and PlanItem, with the plan state machine.

    ShoppingPlan -[Contains]-> FulfillmentLeg -[Contains]-> PlanItem
"""

enum PlanStatus { DRAFT, PROPOSED, ACCEPTED, IN_PROGRESS, COMPLETED, CANCELLED, NEEDS_REVIEW }

enum PlanStrategy { COST_FIRST, CONVENIENCE_FIRST, BALANCED }

enum ItemOutcome { PENDING, PURCHASED, UNAVAILABLE, POSTPONED, CANCELLED }

glob TRANSITIONS: dict = {
    "DRAFT": ["PROPOSED", "CANCELLED"],
    "PROPOSED": ["ACCEPTED", "CANCELLED", "DRAFT"],
    "ACCEPTED": ["IN_PROGRESS", "NEEDS_REVIEW", "CANCELLED"],
    "IN_PROGRESS": ["COMPLETED", "NEEDS_REVIEW", "CANCELLED"],
    "NEEDS_REVIEW": ["ACCEPTED", "CANCELLED"],
    "COMPLETED": [],
    "CANCELLED": []
};

node ShoppingPlan {
    has strategy: PlanStrategy = PlanStrategy.BALANCED,
        status: PlanStatus = PlanStatus.DRAFT,
        cost: dict = {},                   # merchandise, discounts, tax, delivery, tip, transport
        total: float = 0.0,
        active_min: int = 0,
        carried_kg: float = 0.0,
        unmet: list[str] = [],
        explanation: str = "",
        created_at: str = "";

    def move_to(next: PlanStatus) -> bool {
        if next.name not in TRANSITIONS[self.status.name] {
            return False;
        }
        self.status = next;
        return True;
    }
}

"""One store trip or one delivery order. Fees, timing, and carried weight are per leg."""
node FulfillmentLeg {
    has channel: str = "IN_STORE",         # IN_STORE / PICKUP / DELIVERY
        window: str = "",                  # departure or delivery window, e.g. "SAT 14:00-15:30"
        travel_min: int = 0,               # round trip
        shop_min: int = 0,
        transport_cost: float = 0.0,
        fees: dict = {},                   # delivery, service, tip
        lead_time_h: int = 0;              # delivery wait; not active time

    """Items from in-store and pickup legs are carried home by the user."""
    def carried() -> bool {
        return self.channel != "DELIVERY";
    }
}

node PlanItem {
    has name: str,
        qty: int = 1,
        outcome: ItemOutcome = ItemOutcome.PENDING;
}
