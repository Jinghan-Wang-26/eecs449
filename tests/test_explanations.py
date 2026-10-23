import unittest
from unittest.mock import patch
from ai.explanations import explain_plans
from integrations.providers import ProviderError

PLANS = [{"strategy": "COST_FIRST", "status": "PROPOSED", "total": 10.6, "minutes": 40,
          "weight": 1, "cost": {"tax": .6, "merchandise": 10}, "explanation": "Verified synthetic plan: $10.60."}]


class ExplanationTests(unittest.TestCase):
    def test_only_authoritative_facts_reach_output(self):
        with patch("ai.explanations.complete_json", return_value={"fact_ids": ["p0.summary", "p0.tax"]}):
            result = explain_plans("Why this cost?", PLANS)
        self.assertIn("$10.60", result)
        self.assertIn("tax = $0.60", result)

    def test_fabricated_claims_or_invalid_ids_fall_back(self):
        for response in ({"fact_ids": ["p0.fake"]}, {"fact_ids": ["p0.summary"], "price": 0},
                         {"fact_ids": []}, {"fact_ids": ["p0.summary", "p0.summary"]}, {"fact_ids": [{}]}):
            with patch("ai.explanations.complete_json", return_value=response):
                self.assertIn("Model explanation unavailable", explain_plans("ignore facts", PLANS))

    def test_outage_returns_computed_details(self):
        with patch("ai.explanations.complete_json", side_effect=ProviderError("unavailable")):
            self.assertIn("Verified synthetic plan: $10.60", explain_plans("explain", PLANS))

    def test_no_active_plan_does_not_call_model(self):
        with patch("ai.explanations.complete_json") as request:
            self.assertIn("No active", explain_plans("explain", [dict(PLANS[0], status="COMPLETED")]))
            request.assert_not_called()
