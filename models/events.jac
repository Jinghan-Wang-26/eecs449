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
        ignored_count: int = 0,
        last_sent_at: str = "";
}

"""Per-user refresh observations and replay receipts, persisted with the graph."""
node SyncState {
    has receipts: dict = {},
        observations: dict = {},
        syncing: bool = False,
        replan_count: int = 0,
        discovery_counts: dict = {};
}

node ShoppingWorkspace {
    has delivery_quotes: list = [];
    has visit_history: list = [], new_plan_request_ids: list = [];
    has chat_messages: list = [];
    has chat_planning: bool = False, chat_address_pending: bool = False,
        chat_question: str = "", chat_language: str = "en";
    has historical_prices: dict = {};
    has visit_plans: list = [], visit_search: dict = {}, search_radius_m: int = 5000;
    has address_candidates: list = [],
        nearby_stores: list = [],
        product_results: list = [],
        pending_intent: dict = {},
        pending_id: str = "",
        notices: list = [];
}
