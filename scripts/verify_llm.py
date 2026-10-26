"""Explicit, bounded live acceptance. Fixed synthetic prompts; never prints credentials.

Default: two calls. --limit 10 runs the English acceptance set. Not run in CI.
"""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.intents import parse_request
from ai.explanations import explain_plans
from integrations.providers import ProviderError, credentials
from app_settings import stamp

CASES = [
    {"id": "en_needs", "text": "I need two packages of milk and one rice, with a $50 budget. I can walk and am free Saturday 14:00-17:00.",
     "expected": {"needs": {"milk": 2, "rice": 1}, "profile": {"weekly_budget": 50, "transport": ["WALK"], "free_windows": ["SAT 14:00-17:00"]}}},
    {"id": "en_plan", "text": "Compare shopping plans for one package of rice. Budget is 40 dollars. I can walk on Saturday 14:00-17:00.",
     "expected": {"intent": "plan", "needs": {"rice": 1}, "profile": {"weekly_budget": 40, "transport": ["WALK"]}}},
    {"id": "en_budget", "text": "Change my weekly budget to $80 and keep everything else.", "expected": {"intent": "update", "needs": {}, "profile": {"weekly_budget": 80}}},
    {"id": "en_brand", "text": "I need two packages of rice, brand TestBrand, size 5 lb.", "expected": {"needs": {"rice": 2}, "brand": "TestBrand", "size": "5 lb"}},
    {"id": "en_search", "text": "Find supermarkets near my confirmed address.", "expected": {"intent": "search", "needs": {}, "address": ""}},
    {"id": "en_products", "text": "Show historical products from Demo Market in my saved nearby stores.", "expected": {"intent": "products", "store_id": "openprices:123", "needs": {}}},
    {"id": "en_feedback", "text": "I bought rice elsewhere; please record it.", "expected": {"intent": "feedback", "reason": "BOUGHT_ELSEWHERE", "target": "rice"}},
    {"id": "en_explain", "text": "Why does this plan cost more than the other option?", "expected": {"intent": "explain", "needs": {}, "profile": {}}},
    {"id": "en_followup", "text": "Make that three packages; keep everything else.", "history": [{"role": "user", "content": "I need two packages of rice."}, {"role": "assistant", "content": "Please confirm 2 packages of rice."}], "expected": {"needs": {"rice": 3}}},
    {"id": "en_refresh", "text": "Refresh shopping data without changing my saved needs or profile.", "expected": {"intent": "refresh", "needs": {}, "profile": {}}},
]
CONTEXT = {"data_mode": "mock", "has_confirmed_address": True, "needs": [{"type": "rice", "qty": 2}],
           "nearby_stores": [{"id": "openprices:123", "name": "Demo Market", "source": "openprices"}]}


def check(proposal, expected):
    failures = []
    for key, value in expected.items():
        actual = proposal.get(key)
        if key == "needs":
            actual = {n["type"]: n["qty"] for n in proposal["needs"]}
        elif key == "profile":
            if not value:
                actual = proposal["profile"]
            else:
                actual = {k: proposal["profile"].get(k) for k in value}
        elif key in ("brand", "size"):
            actual = proposal["needs"][0].get(key) if proposal["needs"] else None
        elif key in ("reason", "target"):
            actual = proposal.get("feedback", {}).get(key)
        if actual != value:
            failures.append(key)
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, choices=range(1, 11), default=2)
    parser.add_argument("--explanation", action="store_true", help="One additional grounded explanation call")
    parser.add_argument("--output", type=Path, help="Optional sanitized evidence JSON")
    args = parser.parse_args()
    report = {"checked_at": stamp(), "backend": credentials().get("LLM_BACKEND", "api"), "cases": [], "passed": True}
    for case in CASES[:args.limit]:
        row = {"id": case["id"]}
        try:
            proposal = parse_request(case["text"], case.get("history"), CONTEXT)
            failed = check(proposal, case["expected"])
            row.update(passed=not failed, failed_fields=failed)
        except (ValueError, ProviderError) as exc:
            row.update(passed=False, error=str(exc))
        if report["backend"] == "codex":
            from ai.codex_local import LAST_USAGE
            row["usage"] = dict(LAST_USAGE)
        report["cases"].append(row)
        print(json.dumps(row), flush=True)
        if not row["passed"]:
            report["passed"] = False
            break  # Avoid spending more quota when a schema/auth/service check fails.
    if args.explanation and report["passed"]:
        result = explain_plans("Explain the tax in this plan.", [{"strategy": "COST_FIRST", "status": "PROPOSED", "total": 10.6,
            "minutes": 40, "weight": 1, "cost": {"tax": .6, "merchandise": 10}, "explanation": "Synthetic basket: merchandise $10.00 plus tax $0.60, total $10.60."}])
        row = {"id": "grounded_explanation", "passed": result.startswith("Explanation from computed plan facts:") and "$0.60" in result}
        report["cases"].append(row)
        report["passed"] = row["passed"]
        print(json.dumps(row), flush=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
