"""Chat proposes validated changes; confirmation runs the same UI operations."""
import uuid;
import json;
import from ai.intents { parse_request }
import from app_settings { stamp }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from models.graph { owned, items_of }
import from server.workflows { mode_of, workspace_view }


def handle_request(p: UserProfile, text: str, history: list) -> str {
    state = owned(p, ShoppingWorkspace);
    context = {"data_mode": mode_of(p), "has_confirmed_address": bool(p.location),
               "transport": p.transport, "budget": p.weekly_budget,
               "nearby_stores": [{"id": s["id"], "name": s["name"], "source": s.get("source")} for s in state.nearby_stores],
               "needs": [n.product_spec for n in items_of(p) if n.plannable()]};
    proposal = parse_request(text, history, context);
    if proposal["intent"] == "explain" and not proposal["needs"] and not proposal["profile"] and not proposal["address"] {
        plans = workspace_view(p)["plans"];
        if plans { return "\n\n".join([plan["explanation"] for plan in plans]); }
        return "No shopping plan exists yet. Save your needs and constraints, then build plans in the shopping panel.";
    }
    state.pending_intent = proposal;
    state.pending_id = str(uuid.uuid4());
    lines = ["Please review and confirm these changes in the shopping panel:"];
    if proposal["address"] { lines.append("Address to look up: " + proposal["address"]); }
    if proposal["profile"] { lines.append("Profile: " + json.dumps(proposal["profile"], ensure_ascii=False)); }
    for need in proposal["needs"] { lines.append(f"{need['qty']} × {need['type']} {need.get('size', '')}"); }
    if proposal.get("feedback") { lines.append("Feedback: " + json.dumps(proposal["feedback"], ensure_ascii=False)); }
    if proposal.get("store_id") { lines.append("Store for historical product lookup: " + proposal["store_id"]); }
    lines.append("Next operation: " + proposal["intent"]);
    if proposal["question"] { lines.append(proposal["question"]); }
    return "\n".join(lines);
}
