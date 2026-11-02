import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.events { ShoppingWorkspace }
import from models.graph { Owns, owned }
import from server.shopping { shopping_operation }
import from server.visits { visit_context, visit_action }
import from planning.visits { signature }
import from budget.ledger { add_expense, correct_expense, void_expense, budget_view, plan_budget_notes }
import from unittest.mock { patch }
import from planning.visits { candidate }
import from tests.test_visits { STORE, TRAVEL, evidence }

# Saturday; the ISO week runs Monday 2026-10-26 to Sunday 2026-11-01.
glob NOW: str = "2026-10-31T15:00:00-04:00";

def shopper(budget: float = 60.0) -> UserProfile {
    p = UserProfile(data_mode="mock", transport=["WALK"], free_windows=["SAT 14:00-17:00"], weekly_budget=budget);
    p +>:Owns:+> InterestPool();
    return p;
}

"""A live-mode shopper with one synthetic proposed store visit for two packages of rice."""
def visit_user(when: str) -> UserProfile {
    p = UserProfile(data_mode="live", transport=["WALK"], weekly_budget=50, free_windows=["SAT 14:00-17:00"]);
    p +>:Owns:+> InterestPool();
    p.location = {"id": "origin", "address": "Synthetic address", "lat": 42, "lon": -83};
    shopping_operation(p, "save_interest", {"category": "rice", "qty": 2}, when);
    with patch("planning.visits.route", return_value=TRAVEL) {
        plan = candidate(STORE, evidence(), visit_context(p, when), when);
    }
    owned(p, ShoppingWorkspace).visit_plans = [plan];
    return p;
}

def fails(f: any) -> bool {
    try { f(); } except ValueError { return True; }
    return False;
}

test "weekly remaining budget counts only this week's reported spending" {
    p = shopper();
    add_expense(p, {"id": "a", "amount": "12.40", "store": "Kroger - Westgate", "category": "Milk", "spent_at": "2026-10-26"}, NOW);
    add_expense(p, {"id": "b", "amount": 20, "category": "rice", "spent_at": "2026-10-31"}, NOW);
    add_expense(p, {"id": "c", "amount": 30, "category": "rice", "spent_at": "2026-10-25"}, NOW);
    view = budget_view(p, NOW);
    assert view["week_start"] == "2026-10-26" and view["week_end"] == "2026-11-01";
    assert view["spent"] == 32.4 and view["remaining"] == 27.6 and not view["over_budget"];
    assert view["by_category"] == {"milk": 12.4, "rice": 20.0};
    assert [w["spent"] for w in view["recent_weeks"]] == [0, 0, 30.0, 32.4];
    add_expense(p, {"id": "d", "amount": 40, "spent_at": "2026-11-01"}, "2026-11-01T18:00:00-05:00");
    over = budget_view(p, "2026-11-01T18:00:00-05:00");
    assert over["remaining"] == -12.4 and over["over_budget"] and over["by_category"]["uncategorized"] == 40.0;
    # The next Monday starts a fresh week.
    assert budget_view(p, "2026-11-02T09:00:00-05:00")["spent"] == 0;
}

test "no saved budget leaves the remaining amount unknown" {
    p = shopper(0.0);
    add_expense(p, {"id": "a", "amount": 5}, NOW);
    view = budget_view(p, NOW);
    assert view["spent"] == 5.0 and view["remaining"] is None and not view["over_budget"];
}

test "retries are idempotent and invalid entries are rejected" {
    p = shopper();
    entry = {"id": "r1", "amount": "9.99", "store": "Target", "spent_at": "2026-10-30"};
    assert add_expense(p, entry, NOW) == "Expense recorded.";
    assert add_expense(p, entry, NOW) == "Expense already recorded.";
    undated = {"id": "r2", "amount": "4"};
    add_expense(p, undated, NOW);
    assert add_expense(p, undated, "2026-10-31T15:00:07-04:00") == "Expense already recorded.";
    assert fails(lambda: add_expense(p, entry | {"amount": "10"}, NOW));
    assert fails(lambda: add_expense(p, {"id": "x", "amount": "0"}, NOW));
    assert fails(lambda: add_expense(p, {"id": "x", "amount": "nan"}, NOW));
    assert fails(lambda: add_expense(p, {"id": "x", "amount": "20000"}, NOW));
    assert fails(lambda: add_expense(p, {"id": "x", "amount": "3", "spent_at": "2026-11-05"}, NOW));
    assert fails(lambda: add_expense(p, {"id": "x", "amount": "3", "spent_at": "not a date"}, NOW));
    assert fails(lambda: add_expense(p, {"amount": "3"}, NOW));
    assert budget_view(p, NOW)["spent"] == 13.99;
}

test "corrections keep history and voided entries leave the totals" {
    p = shopper();
    add_expense(p, {"id": "e", "amount": 15, "category": "coffee", "spent_at": "2026-10-29"}, NOW);
    assert correct_expense(p, {"id": "e", "amount": "14.49"}, NOW) == "Expense corrected.";
    assert correct_expense(p, {"id": "e", "amount": "14.49"}, NOW) == "No changes to save.";
    view = budget_view(p, NOW);
    entry = view["entries"][0];
    assert view["spent"] == 14.49 and entry["category"] == "coffee";
    assert [h["amount"] for h in entry["history"]] == [15.0];
    assert void_expense(p, {"id": "e", "reason": "Duplicate receipt"}, NOW) == "Expense removed from totals.";
    assert void_expense(p, {"id": "e"}, NOW) == "Expense already removed.";
    view = budget_view(p, NOW);
    assert view["spent"] == 0 and view["entries"][0]["voided"] and view["entries"][0]["void_reason"] == "Duplicate receipt";
    assert fails(lambda: correct_expense(p, {"id": "e", "amount": 1}, NOW));
    assert fails(lambda: correct_expense(p, {"id": "missing", "amount": 1}, NOW));
}

test "panel actions return the budget without triggering a refresh" {
    p = shopper();
    out = shopping_operation(p, "expense_add", {"id": "p1", "amount": "7.5", "category": "eggs"}, NOW);
    assert out["message"] == "Expense recorded." and out["budget"]["spent"] == 7.5 and out["budget"]["remaining"] == 52.5;
    out = shopping_operation(p, "expense_correct", {"id": "p1", "amount": "8"}, NOW);
    assert out["budget"]["spent"] == 8.0;
    out = shopping_operation(p, "expense_void", {"id": "p1"}, NOW);
    assert out["budget"]["spent"] == 0;
}

test "amounts reported on a store visit enter the ledger once" {
    when = "2030-01-01T10:00:00-05:00";
    p = visit_user(when);
    plan = owned(p, ShoppingWorkspace).visit_plans[0];
    plan["input_signature"] = signature(visit_context(p, when));
    visit_action(p, {"key": plan["key"], "action": "accept", "acknowledge_unknowns": True}, when);
    outcome = {"key": plan["key"], "action": "outcome", "category": "rice", "outcome": "PARTIAL", "bought_qty": 1, "actual_paid": "3.25"};
    visit_action(p, outcome, when);
    visit_action(p, outcome, when);
    view = budget_view(p, when);
    entries = list(view["entries"]);
    assert view["spent"] == 3.25 and len(entries) == 1;
    entry = view["entries"][0];
    assert entry["source"] == "visit" and entry["category"] == "rice" and entry["store"] == plan["store"]["name"];
}

test "open plans get advisory notes against the remaining budget" {
    p = shopper(60.0);
    add_expense(p, {"id": "w", "amount": 45, "spent_at": "2026-10-30"}, NOW);
    plans = [
        {"key": "fits", "status": "PROPOSED", "total": 12.0},
        {"key": "over", "status": "PROPOSED", "estimated_total": 20.5},
        {"key": "partial", "status": "ACCEPTED", "estimated_total": None, "current_subtotal": 16.0},
        {"key": "history-only", "status": "PROPOSED", "reference_subtotal": 99.0},
        {"key": "done", "status": "COMPLETED", "total": 80.0}
    ];
    notes = plan_budget_notes(p, plans, NOW);
    assert sorted(notes.keys()) == ["over", "partial"];
    assert notes["over"] == "Estimated $20.50 is more than the $15.00 left this week ($45.00 already spent this week).";
    assert notes["partial"].startswith("Known prices alone ($16.00) exceed the $15.00 left");
    add_expense(p, {"id": "x", "amount": 20, "spent_at": "2026-10-31"}, NOW);
    assert plan_budget_notes(p, plans, NOW)["fits"] == "This week's budget is used up ($65.00 already spent this week).";
    assert plan_budget_notes(shopper(0.0), plans, NOW) == {};
}

test "demo plans in the panel response carry budget notes" {
    p = UserProfile(data_mode="mock", transport=["WALK", "BUS"], free_windows=["SAT 14:00-17:00"], weekly_budget=100);
    p +>:Owns:+> InterestPool();
    add_expense(p, {"id": "spent", "amount": 95, "spent_at": "2026-10-27"}, NOW);
    shopping_operation(p, "save_interest", {"category": "rice", "qty": 1}, NOW);
    out = shopping_operation(p, "plan", {}, NOW);
    plans = list(out["workspace"]["plans"]);
    assert len(plans) > 0;
    notes = dict(out["workspace"]["budget_notes"]);
    assert all([notes.get(plan["key"], "").startswith("Estimated $") for plan in plans if plan["total"] > 5]);
}
