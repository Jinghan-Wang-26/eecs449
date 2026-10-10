"""ShoppingPlan and PlanItem, with the plan state machine."""

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

node PlanItem {
    has name: str,
        qty: int = 1,
        channel: str = "IN_STORE",         # IN_STORE / PICKUP / DELIVERY
        outcome: ItemOutcome = ItemOutcome.PENDING;
}
