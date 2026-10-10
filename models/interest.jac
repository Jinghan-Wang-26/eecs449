"""InterestPool and InterestItem. Items describe needs only; prices live in Offer."""

enum InterestKind { NEED, REPLENISH, WATCH, DISCOVER }

enum InterestStatus { ACTIVE, PAUSED, ARCHIVED }

node InterestPool {}

node InterestItem {
    has product_spec: dict,                # {"type": "milk", "size": "1 gal", "brand": "", "qty": 1, "substitutes": "ask"}
        kind: InterestKind = InterestKind.NEED,
        status: InterestStatus = InterestStatus.ACTIVE,
        priority: int = 2,                 # 1 high .. 3 low
        needed_by: str = "",
        target_price: float = 0.0,         # WATCH only
        interest_score: float = 0.0,       # DISCOVER only; separate from priority
        last_purchased_at: str = "",
        replenishment_days: int = 0,
        source: str = "USER",              # USER / HISTORY / INFERRED
        confidence: float = 1.0,
        feedback_history: list[dict] = [], # [{"event_id": ..., "reason": ..., "at": ...}]
        locked: bool = False,
        snoozed_until: str = "";

    """NEED and REPLENISH items enter planning. DISCOVER needs confirmation first."""
    def plannable() -> bool {
        return self.status == InterestStatus.ACTIVE
            and (self.kind == InterestKind.NEED or self.kind == InterestKind.REPLENISH);
    }
}
