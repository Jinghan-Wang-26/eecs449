"""FeedbackEvent and Reminder. Both point at what they are about through About edges."""

enum FeedbackReason {
    PURCHASED,
    BOUGHT_ELSEWHERE,
    OUT_OF_STOCK,
    BUSY,
    HAVE_AT_HOME,
    DISLIKED,
    TOO_EXPENSIVE,
    INCONVENIENT
}

enum ReminderStatus { PENDING, SENT, SNOOZED, DISMISSED, IGNORED }

"""Holds processed event IDs so feedback is applied at most once."""
node EventLog {
    has seen: list[str] = [];
}

node FeedbackEvent {
    has event_id: str,
        reason: FeedbackReason,
        text: str = "",
        at: str = "",
        until: str = "";                   # HAVE_AT_HOME: snooze replenishment until this time
}

node Inbox {}

node Reminder {
    has dedup_key: str,                    # "replenish:<item>:<date>", "price:<offer>:<price>"
        kind: str = "",                    # DEADLINE / REPLENISH / PRICE_DROP / RESTOCK / DISCOVER / PLAN_CHANGE
        message: str = "",
        fire_at: str = "",
        created_at: str = "",
        status: ReminderStatus = ReminderStatus.PENDING,
        ignored_count: int = 0;
}
