"""Spending ledger and weekly remaining budget.

Only amounts the user actually reports are recorded: manual entries and the
"actual amount paid" field of real-store visits. Estimates, quotes and demo
prices never enter the ledger. Corrections keep the previous values; removal
voids an entry so weekly totals stay auditable.
"""

import math;
import from datetime { date, timedelta }
import from app_settings { get_settings, stamp, instant, week_key }
import from models.profile { UserProfile }
import from models.events { SpendingLedger }
import from typing { cast }
import from models.graph { owned }

glob MAX_AMOUNT: float = 10000.0,
     FIELDS: list = ["amount", "store", "category", "spent_at", "note"];

"""Round to whole cents."""
def cents(value: float) -> float {
    return float(f"{value:.2f}");
}

def clean_amount(value: any) -> float {
    amount: float = 0.0;
    try { amount = cents(float(str(value))); }
    except (TypeError, ValueError) { raise ValueError("Enter the amount paid in USD."); }
    if not math.isfinite(amount) or amount <= 0 or amount > MAX_AMOUNT {
        raise ValueError("Amount must be greater than 0 and at most 10,000 USD.");
    }
    return amount;
}

def clean_text(value: any, name: str, limit: int) -> str {
    text = str(value or "").strip();
    if len(text) > limit { raise ValueError(f"{name} must be at most {limit} characters."); }
    return text;
}

"""Accepts a date (YYYY-MM-DD) or full timestamp; a bare date means local noon."""
def clean_time(value: any, now: str, cfg: dict) -> str {
    text = str(value or "").strip();
    if text == "" { return now; }
    if len(text) == 10 { text += "T12:00:00"; }
    try { at = stamp(text, cfg); }
    except ValueError { raise ValueError("Enter the purchase date as YYYY-MM-DD."); }
    if instant(at, cfg) > instant(now, cfg) + timedelta(minutes=5) {
        raise ValueError("Purchase date cannot be in the future.");
    }
    return at;
}

def clean_entry(data: dict, now: str, cfg: dict) -> dict {
    return {"amount": clean_amount(data.get("amount")),
            "store": clean_text(data.get("store"), "Store", 80),
            "category": clean_text(data.get("category"), "Category", 40).lower(),
            "spent_at": clean_time(data.get("spent_at"), now, cfg),
            "note": clean_text(data.get("note"), "Note", 200)};
}

def find_entry(ledger: SpendingLedger, entry_id: str) -> dict | None {
    for e in ledger.entries {
        if e["id"] == entry_id { return cast(dict, e); }
    }
    return None;
}

def same_values(row: dict, values: dict) -> bool {
    return all([row[k] == values[k] for k in FIELDS]);
}

"""Record a payment. A retried request with the same id and values is a no-op."""
def add_expense(p: UserProfile, data: dict, now: str, source: str = "manual", settings: dict = {}) -> str {
    cfg = get_settings(settings);
    now = stamp(now, cfg);
    entry_id = clean_text(data.get("id"), "Entry id", 120);
    if entry_id == "" { raise ValueError("Missing request id; reload and retry."); }
    values = clean_entry(data, now, cfg);
    ledger = cast(SpendingLedger, owned(p, SpendingLedger));
    existing = find_entry(ledger, entry_id);
    if existing is not None {
        # A retry without a date means "when first recorded", not the retry's clock.
        if str(data.get("spent_at") or "").strip() == "" { values["spent_at"] = existing["spent_at"]; }
        if same_values(existing, values) and existing["source"] == source { return "Expense already recorded."; }
        raise ValueError("This expense id was already used with different values.");
    }
    row = {"id": entry_id, "source": source, "created_at": now, "voided": False, "history": []} | values;
    ledger.entries = list(ledger.entries) + [row];
    return "Expense recorded.";
}

"""Change an row's values, keeping what it said before."""
def correct_expense(p: UserProfile, data: dict, now: str, settings: dict = {}) -> str {
    cfg = get_settings(settings);
    now = stamp(now, cfg);
    ledger = cast(SpendingLedger, owned(p, SpendingLedger));
    row = find_entry(ledger, str(data.get("id", "")));
    if row is None or row["voided"] { raise ValueError("Expense not found or already removed."); }
    merged = {k: data.get(k, row[k]) for k in FIELDS};
    values = clean_entry(merged, now, cfg);
    if same_values(row, values) { return "No changes to save."; }
    previous = {k: row[k] for k in FIELDS} | {"changed_at": now};
    row.update(values);
    row["history"] = list(row["history"]) + [previous];
    ledger.entries = list(ledger.entries);
    return "Expense corrected.";
}

def void_expense(p: UserProfile, data: dict, now: str, settings: dict = {}) -> str {
    cfg = get_settings(settings);
    ledger = cast(SpendingLedger, owned(p, SpendingLedger));
    row = find_entry(ledger, str(data.get("id", "")));
    if row is None { raise ValueError("Expense not found."); }
    if row["voided"] { return "Expense already removed."; }
    row["voided"] = True;
    row["voided_at"] = stamp(now, cfg);
    row["void_reason"] = clean_text(data.get("reason"), "Reason", 200);
    ledger.entries = list(ledger.entries);
    return "Expense removed from totals.";
}

"""Monday-to-Sunday bounds of the ISO week containing `now`, as local dates."""
def week_bounds(now: str, cfg: dict) -> dict {
    today = instant(now, cfg).date();
    start = today - timedelta(days=today.weekday());
    return {"start": start.isoformat(), "end": (start + timedelta(days=6)).isoformat()};
}

def budget_view(p: UserProfile, now: str, settings: dict = {}) -> dict {
    cfg = get_settings(settings);
    now = stamp(now, cfg);
    ledger = cast(SpendingLedger, owned(p, SpendingLedger));
    this_week = week_key(now, cfg);
    live = [e for e in ledger.entries if not e["voided"]];
    week_entries = [e for e in live if week_key(str(e["spent_at"]), cfg) == this_week];
    spent = cents(sum([float(e["amount"]) for e in week_entries]));
    budget: float = float(p.weekly_budget);
    remaining = cents(budget - spent) if budget > 0 else None;
    by_category: dict[str, float] = {};
    for e in week_entries {
        name = str(e["category"] or "uncategorized");
        so_far: float = by_category[name] if name in by_category else 0.0;
        by_category[name] = cents(so_far + float(e["amount"]));
    }
    start = date.fromisoformat(str(week_bounds(now, cfg)["start"]));
    recent = [];
    for back in range(3, -1, -1) {
        day = start - timedelta(weeks=back);
        key = week_key(day.isoformat() + "T12:00:00", cfg);
        recent.append({"week": key, "start": day.isoformat(),
                       "spent": cents(sum([float(e["amount"]) for e in live if week_key(str(e["spent_at"]), cfg) == key]))});
    }
    entries = sorted(list(ledger.entries), key=lambda e: dict: str(e["spent_at"]), reverse=True)[:50];
    return {"week": this_week, "week_start": week_bounds(now, cfg)["start"], "week_end": week_bounds(now, cfg)["end"],
            "weekly_budget": budget, "spent": spent, "remaining": remaining,
            "over_budget": remaining is not None and remaining < 0,
            "by_category": by_category, "recent_weeks": recent, "entries": entries};
}

"""Known current cost of a plan view, and whether it covers the whole basket.
Historical reference subtotals are evidence, not a cost, and are never used."""
def known_cost(plan: dict) -> dict {
    for field in ["total", "estimated_total"] {
        if plan.get(field) is not None { return {"amount": plan[field], "complete": True}; }
    }
    for field in ["current_subtotal", "retail_subtotal"] {
        if plan.get(field) is not None { return {"amount": plan[field], "complete": False}; }
    }
    return {"amount": None, "complete": False};
}

"""Advisory notes comparing open plans with this week's remaining budget.
They never block acceptance; the planners' own budget checks are unchanged."""
def plan_budget_notes(p: UserProfile, plans: list, now: str, settings: dict = {}) -> dict {
    view = budget_view(p, now, settings);
    if view["remaining"] is None { return {}; }
    left = view["remaining"];
    notes = {};
    for plan in plans {
        if plan.get("status") not in ["PROPOSED", "ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"] { continue; }
        cost = known_cost(dict(plan));
        if cost["amount"] is None or cost["amount"] <= left { continue; }
        spent = f"${view['spent']:.2f} already spent this week";
        if left <= 0 {
            notes[plan["key"]] = f"This week's budget is used up ({spent}).";
        } elif cost["complete"] {
            notes[plan["key"]] = f"Estimated ${cost['amount']:.2f} is more than the ${left:.2f} left this week ({spent}).";
        } else {
            notes[plan["key"]] = f"Known prices alone (${cost['amount']:.2f}) exceed the ${left:.2f} left this week ({spent}).";
        }
    }
    return notes;
}
