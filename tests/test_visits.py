"""Synthetic historical evidence and route responses; no external calls."""
import copy
import unittest
from unittest.mock import patch
from planning import visits as v
from integrations import openprices as op
from integrations.providers import ProviderError, _CACHE

NOW = "2030-01-01T10:00:00-05:00"
STORE = {"id":"openprices:10", "external_id":"10", "name":"Synthetic supermarket", "address":"Test street", "source":"openprices", "lat":42.001, "lon":-83, "distance_m":100}
ROW = {"record_id":1, "name":"Brown rice", "brand":"Test", "size_label":"1 kg", "weight_kg":1,
       "recorded_on":"2029-12-01", "location_id":"10", "price":3, "price_per":"UNIT", "currency":"USD", "discounted":False, "labels":[], "categories":["en:rices"], "source_url":"https://prices.openfoodfacts.org/prices/1", "proof_url":"https://prices.openfoodfacts.org/proofs/2"}
TRAVEL = {"min":10, "walk_min":5, "cost":0, "source":"geoapify", "valid_until":"2030-01-01T11:00:00-05:00"}

def context():
    return {"origin":{"id":"origin", "address":"Public example", "lat":42, "lon":-83}, "radius_m":5000,
            "needs":[{"type":"rice", "qty":2}], "profile":{"transport":["WALK"], "max_walk_min":15, "free_windows":["SAT 14:00-17:00"], "weekly_budget":50, "carry_limit_kg":6, "dietary":[], "transport_cost":-1}}

def evidence(rows=None):
    return {"records": [copy.deepcopy(ROW)] if rows is None else rows, "checked":1, "partial":True, "notice":""}

class VisitRecommendationTests(unittest.TestCase):
    def candidate(self, ctx=None, rows=None, travel=None):
        with patch.object(v, "route", return_value=travel or TRAVEL):
            return v.candidate(STORE, evidence(rows), ctx or context(), NOW)

    def test_historical_reference_and_route_window_never_current_quote(self):
        plan = self.candidate()
        self.assertEqual(plan["reference_subtotal"], 6)
        self.assertEqual(plan["matched"], 1)
        self.assertEqual(plan["route"]["window"], "SAT 14:00-14:30")
        self.assertEqual(plan["known_net_weight_kg"], 2)
        self.assertTrue(plan["accept_allowed"])
        self.assertNotIn("current_price", plan)
        self.assertIn("not by today's price", plan["explanation"])
        self.assertIn("origin=42%2C-83", plan["navigation_url"])

    def test_wrong_location_future_date_and_ingredient_false_matches_excluded(self):
        for changes in ({"location_id":"11"}, {"recorded_on":"2040-01-01"}, {"recorded_on":"Unknown"}, {"name":"rice crackers"}):
            self.assertEqual(self.candidate(rows=[dict(ROW, **changes)])["matched"], 0)
        self.assertFalse(v.match_record({"type":"milk"}, dict(ROW, name="Milk chocolate", categories=[]), [], NOW))

    def test_explicit_specs_and_diet_do_not_become_automatic_substitutions(self):
        c = context(); c["needs"][0]["brand"] = "Different"
        self.assertEqual(self.candidate(c)["matched"], 0)
        c = context(); c["profile"]["dietary"] = ["vegan"]
        self.assertEqual(self.candidate(c)["matched"], 0)
        self.assertEqual(self.candidate(c, [dict(ROW, labels=["en:vegan"])])["matched"], 1)
        c = context(); c["needs"][0]["type"] = "大米"
        self.assertEqual(self.candidate(c)["matched"], 1)

    def test_discount_other_currency_and_per_kg_never_multiply_package_count(self):
        for changes in ({"discounted":True}, {"currency":"EUR"}, {"price_per":"KILOGRAM"}, {"price_per":"not specified"}, {"price":None}):
            plan = self.candidate(rows=[dict(ROW, **changes)])
            self.assertEqual(plan["matched"], 1)
            self.assertIsNone(plan["reference_subtotal"])
            self.assertEqual(plan["priced_needs"], 0)

    def test_latest_record_used_instead_of_cherry_picking_cheapest(self):
        plan = self.candidate(rows=[dict(ROW, price=1, recorded_on="2020-01-01"), dict(ROW, price=9, recorded_on="2029-12-31", record_id=2)])
        self.assertEqual(plan["reference_subtotal"], 18)

    def test_unknown_coverage_budget_weight_and_stock_are_visible(self):
        c = context(); c["needs"].append({"type":"milk", "qty":1}); c["profile"]["weekly_budget"] = 1
        plan = self.candidate(c)
        self.assertEqual(plan["matched"], 1)
        self.assertFalse(plan["weight_complete"])
        self.assertTrue(any("exceeds" in x for x in plan["warnings"]))
        self.assertTrue(any("Current budget feasibility is unknown" in x for x in plan["warnings"]))
        self.assertTrue(self.candidate(rows=[])["accept_allowed"])
        self.assertIsNone(self.candidate(rows=[])["reference_subtotal"])

    def test_walk_time_weight_and_unsupported_transit_block_acceptance(self):
        changes = [{"max_walk_min":1}, {"free_windows":["SAT 14:00-14:10"]}, {"free_windows":[]}, {"carry_limit_kg":1}]
        for change in changes:
            c=context(); c["profile"].update(change)
            self.assertFalse(self.candidate(c)["accept_allowed"])
        c=context(); c["profile"]["transport"]=["BUS"]
        with patch.object(v, "route") as call:
            plan=v.candidate(STORE, evidence(), c, NOW)
            call.assert_not_called(); self.assertFalse(plan["accept_allowed"])

    def test_route_failure_does_not_turn_distance_into_fake_travel_time(self):
        with patch.object(v, "route", side_effect=ProviderError("outage")):
            plan=v.candidate(STORE, evidence(), context(), NOW)
        self.assertIsNone(plan["route"]); self.assertFalse(plan["accept_allowed"])

    def test_recommendation_uses_only_openprices_and_ranks_coverage_then_travel(self):
        second=dict(STORE, id="map:2", external_id="", source="geoapify", name="Location only", lat=42.0001)
        with patch.object(v, "nearby_with_history", return_value={"stores":[second,STORE],"notices":[]}) as search, patch.object(v, "recommendation_records", return_value=evidence()), patch.object(v, "route", return_value=TRAVEL):
            result=v.recommend(context(), NOW)
            self.assertFalse(search.call_args.kwargs["include_kroger"])
            self.assertEqual(result["plans"][0]["store"]["id"], STORE["id"])
            self.assertEqual(result["plans"][1]["matched"],0)

    def test_missing_inputs_do_not_query_providers(self):
        with patch.object(v, "nearby_with_history") as search:
            for change in ({"origin":{}},{"needs":[]}):
                with self.assertRaises(ValueError):v.recommend(dict(context(), **change),NOW)
            search.assert_not_called()

class HistoricalSearchTests(unittest.TestCase):
    def test_bounded_targeted_queries_remain_location_bound_and_cached(self):
        _CACHE.clear()
        data={"items":[{"id":1,"location_id":10,"proof_id":2,"price":3,"date":"2029-12-01","product_name":"Rice"},
                       {"id":3,"location_id":11,"proof_id":2,"price":1}],"pages":12}
        with patch.object(op, "request_json", return_value=data) as request:
            result=op.recommendation_records("10",["rice","rice"])
            self.assertEqual(request.call_count,3)
            self.assertTrue(all(c.kwargs["params"]["location_id"]=="10" for c in request.call_args_list))
            self.assertEqual(request.call_args.kwargs["params"]["product__categories_tags__contains"],"en:rices")
            self.assertEqual(len(result["records"]),1)
            self.assertTrue(result["partial"])
            op.recommendation_records("10",["rice"])
            self.assertEqual(request.call_count,3)

    def test_partial_provider_failure_preserves_available_records(self):
        _CACHE.clear()
        with patch.object(op,"request_json", side_effect=[ProviderError("unavailable"), {"items":[],"pages":1}]):
            result=op.recommendation_records("10",[])
            self.assertTrue(result["partial"]); self.assertIn("failed",result["notice"])

class LiveDataRegressionTests(unittest.TestCase):
    def test_milk_tea_and_unrequested_plant_milk_are_not_dairy_milk(self):
        for name in ("Organic Mothers Milk Tea", "Coconut Milk", "Almond milk", "Milk chocolate"):
            self.assertFalse(v.match_record({"type":"milk"}, dict(ROW, name=name, categories=[]), [], NOW))
        self.assertTrue(v.match_record({"type":"coconut milk"}, dict(ROW, name="Coconut Milk", categories=[]), [], NOW))

    def test_barcode_product_unit_price_and_unknown_basis_are_distinct(self):
        row={"id":1,"location_id":10,"proof_id":2,"price":3,"type":"PRODUCT","product_code":"12345678","price_per":None}
        record=op.normalize_records({"items":[row]},"10")[0]
        self.assertEqual(record["price_per"],"UNIT")
        self.assertIsNone(record["raw_price_per"])
        row["type"]="CATEGORY"; row["product_code"]=""
        self.assertEqual(op.normalize_records({"items":[row]},"10")[0]["price_per"],"not specified")

    def test_device_reverse_geocode_keeps_device_coordinates(self):
        from integrations import providers
        _CACHE.clear()
        with patch.object(providers,"required",return_value="synthetic"), patch.object(providers,"request_json", return_value={"results":[{"formatted":"Public location","lat":1,"lon":1}]}):
            result=providers.reverse_geocode(42,-83,25)[0]
        self.assertEqual((result["lat"],result["lon"]),(42,-83))
        self.assertEqual(result["accuracy_m"],25)
        with self.assertRaises(ProviderError): providers.reverse_geocode(91,-83,25)
