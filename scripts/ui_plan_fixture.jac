"""Synthetic UI stress data built from existing offline policy/GTFS fixtures.

Only browser verification invokes this script; the application never imports it.
"""
import json;
import copy;
import from tests.test_retail_visits { current_plan }
import from tests.test_transit { TransitVisitTests }

with entry {
    plan = copy.deepcopy(current_plan());
    plan["key"] = "layout-recommended";
    plan["store"]["name"] = "Synthetic Market - Plymouth and Nixon Neighborhood Grocery";
    plan["store"]["address"] = "100 Example Street, Ann Arbor, MI 48105";
    plan["origin_label"] = "100 Synthetic Starting Point, Ann Arbor, MI 48105";
    plan["route"] = TransitVisitTests().plan();
    plan["estimated_total"] = None;
    plan["transport_estimate"] = None;
    plan["tax_estimate"] = 0;
    plan["tax_basis"] = "STATE_RULES";
    plan["tax_note"] = "Michigan: groceries exempt, household and personal-care products use the applicable state rate. This is an estimate; check the receipt.";
    plan["comparison_labels"] = ["Balanced"];
    plan["explanation"] = "Synthetic layout fixture: current item snapshots, a scheduled bus trip and an unknown fare. No live retailer request was made.";
    plans = [plan];
    alternative = copy.deepcopy(plan);
    alternative["key"] = "layout-alternative";
    alternative["store"]["name"] = "Synthetic Neighborhood Cooperative and International Food Market";
    alternative["comparison_labels"] = ["Alternative"];
    plans.append(alternative);
    for idx in range(2) {
        unknown = copy.deepcopy(current_plan([]));
        unknown["key"] = f"layout-unknown-{idx}";
        unknown["store"]["name"] = f"Synthetic store {idx+1} without product data";
        plans.append(unknown);
    }
    print(json.dumps(plans));
}
