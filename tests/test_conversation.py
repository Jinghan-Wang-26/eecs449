import jaclang  # Enable direct imports of the migrated .jac modules.
import unittest
from ai.conversation import missing_fields, question, language, plan_summary
from ai.intents import validate_intent

class ConversationTests(unittest.TestCase):
    def context(self):
        return {"data_mode":"live", "has_confirmed_address":True, "address_pending":False, "needs":[{"type":"milk","qty":1}], "transport":["WALK"], "free_windows":["SAT 14:00-17:00"], "budget":0}

    def test_only_required_fields_block_real_visit(self):
        c=self.context(); self.assertEqual(missing_fields(c),[])
        c.update(transport=["BUS"], free_windows=[])
        self.assertEqual(missing_fields(c),["transport","free_windows"])
        self.assertIn("bus",question(c,"transport","en"))
        self.assertEqual(c["transport"],["BUS"])

    def test_pending_new_address_blocks_use_of_old_confirmed_location(self):
        c=self.context();c["address_pending"]=True
        self.assertEqual(missing_fields(c),["address"])
        c["address_candidates"]=[{"address":"Synthetic address A"},{"address":"Synthetic address B"}]
        self.assertIn("2. Synthetic address B",question(c,"address","en"))

    def test_output_is_english_even_with_a_legacy_language_preference(self):
        self.assertEqual(language("2", "zh"), "en")
        self.assertEqual(language("samedi", "fr"), "en")
        self.assertEqual(question(self.context(), "needs", "zh"), question(self.context(), "needs", "en"))

    def test_address_choice_rejects_invalid_types_and_range(self):
        for choice in (True,0,6,"1",1.5):
            with self.assertRaises(ValueError):validate_intent({"intent":"update","address_choice":choice})
        self.assertEqual(validate_intent({"intent":"update","address_choice":2})["address_choice"],2)

    def test_mock_budget_is_required_but_live_unknown_budget_is_allowed(self):
        c=self.context();c["data_mode"]="mock"
        self.assertEqual(missing_fields(c),["weekly_budget"])

    def test_summary_never_claims_blocked_store_is_acceptable(self):
        workspace={"visit_plans":[{"status":"PROPOSED","accept_allowed":False,"store":{"name":"Synthetic","address":"Test"},"items":[{"qty":1,"category":"milk"}],"route":None,"matched":0,"need_count":1,"reference_subtotal":None,"blockers":["No supported route"],"route_notices":["BUS unsupported"]}]}
        text=plan_summary(workspace,"en")
        self.assertIn("0 can be reviewed and accepted",text)
        self.assertIn("BUS unsupported",text)
        self.assertIn("price unknown",text)
        self.assertNotIn("USD 0",text)
