"""Opt-in real model test on a detached synthetic user; not collected by jac test.
Run from the repository: LLM_BACKEND=codex jac run scripts/verify_chat.jac
Three model calls: intent, explanation intent, grounded fact selection.
"""
import json;
import from app_settings { stamp }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.events { ShoppingWorkspace }
import from models.graph { Owns, owned, items_of }
import from harness.agent { handle_request }
import from server.shopping { shopping_operation }

with entry {
    p = UserProfile(data_mode="mock", carry_limit_kg=20, max_walk_min=30);
    p +>:Owns:+> InterestPool();
    now = stamp();
    reply = handle_request(p, "Compare shopping plans for one package of rice. Budget is 50 dollars. I can walk on Saturday 14:00-17:00.", []);
    state = owned(p, ShoppingWorkspace);
    assert state.pending_id == "" and len(items_of(p)) == 1;
    view = shopping_operation(p, "view", {}, now);
    assert len([n for n in items_of(p) if n.plannable()]) == 1;
    assert p.weekly_budget == 50;
    assert len(view["workspace"]["plans"]) > 0, view["message"];
    assert all([plan["status"] == "PROPOSED" for plan in view["workspace"]["plans"]]);
    print(json.dumps({"check": "live_chat_auto_plan", "passed": True, "plans": len(view["workspace"]["plans"])}));
    explanation = handle_request(p, "Explain the tax in these plans, without changing anything.", []);
    assert explanation.startswith("Explanation from computed plan facts:");
    assert state.pending_id == "";
    assert all([plan["status"] == "PROPOSED" for plan in view["workspace"]["plans"]]);
    print(json.dumps({"check": "live_chat_grounded_explanation", "passed": True}));
}
