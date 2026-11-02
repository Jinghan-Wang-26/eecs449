"""Conversational profile collection; explicit feedback/plan acceptance remains separate."""
import uuid;
import json;
import from ai.intents { parse_request }
import from ai.conversation { language, missing_fields, question, saved_message, plan_summary, needs_variety, variety_question }
import from ai.explanations { explain_plans }
import from app_settings { stamp, get_settings }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from models.graph { owned, items_of }
import from server.workflows { mode_of, workspace_view, workflow }
import from server.shopping { shopping_operation }
import from planning.schedule { conversation_clock }


def conversation_context(p: UserProfile) -> dict {
    state = owned(p, ShoppingWorkspace);
    return {"data_mode": mode_of(p), "has_confirmed_address": bool(p.location),
        "transport": p.transport, "budget": p.weekly_budget, "free_windows": p.free_windows,
        "max_walk_min": p.max_walk_min, "max_transfers": p.max_transfers, "carry_limit_kg": p.carry_limit_kg,
        "address_pending": state.chat_address_pending,
        "address_candidates": [{"address": c["address"]} for c in state.address_candidates],
        "current_question": state.chat_question, "planning_requested": state.chat_planning,
        **conversation_clock(p.location),
        "nearby_stores": [{"id": s["id"], "name": s["name"], "source": s.get("source")} for s in state.nearby_stores],
        "needs": [n.product_spec for n in items_of(p) if n.plannable()]};
}


def continue_plan(p: UserProfile, prefix: str) -> str {
    state = owned(p, ShoppingWorkspace);
    context = conversation_context(p);
    missing = list(missing_fields(context));
    if missing {
        reply = question(context, missing[0], state.chat_language);
        state.chat_question = reply;
        return prefix + reply;
    }
    try { result = shopping_operation(p, "plan", {}, str(stamp())); }
    except ValueError as err {
        state.chat_question = str(err);
        return prefix + ("Your information is saved, but planning failed: ") + str(err);
    }
    state.chat_question = "";
    view = result["workspace"];
    if mode_of(p) == "live" {
        state.chat_planning = not any([v["accept_allowed"] for v in view["visit_plans"] if v["status"] == "PROPOSED"]);
        reply = plan_summary(view, state.chat_language);
    } else {
        state.chat_planning = not bool(view["plans"]);
        reply = str(result["message"]);
    }
    if state.chat_planning { state.chat_question = reply; }
    return prefix + reply;
}


def handle_request(p: UserProfile, text: str, history: list) -> str {
    state = owned(p, ShoppingWorkspace);
    state.chat_language = language(text, state.chat_language);
    context = conversation_context(p);
    context["missing_fields"] = missing_fields(context);
    proposal = dict(parse_request(text, history, context));
    lang = state.chat_language;
    now = str(stamp());
    if proposal["intent"] == "stop" {
        state.chat_planning = False; state.chat_question = ""; state.chat_address_pending = False;
        state.pending_intent = {}; state.pending_id = "";
        return "Paused conversational planning. Saved information and accepted plans are unchanged.";
    }
    # Feedback can archive needs; keep its explicit review action.
    if proposal.get("feedback") or proposal["intent"] == "feedback" {
        state.pending_intent = proposal; state.pending_id = str(uuid.uuid4());
        return ("Please review the purchase feedback using Confirm changes in the shopping panel: ") + json.dumps(proposal.get("feedback", {}), ensure_ascii=False);
    }
    if proposal["intent"] == "explain" and not proposal["needs"] and not proposal["profile"] and not proposal["address"] and not proposal.get("address_choice") {
        view = workspace_view(p);
        active_visits = [v for v in view["visit_plans"] if v["status"] in ["PROPOSED", "ACCEPTED", "IN_PROGRESS", "NEEDS_REVIEW"]];
        if mode_of(p) == "live" and active_visits {
            return "\n\n".join([str(v["explanation"]) + "\n" + "\n".join(list(v["warnings"]) + list(v["blockers"]) + list(v["route_notices"])) for v in active_visits]);
        }
        if view["plans"] { return str(explain_plans(text, view["plans"])); }
        return question(context, list(missing_fields(context))[0], lang) if missing_fields(context) else ("Ask me to generate a shopping plan.");
    }
    # A new conversational turn supersedes old draft-only requests, never accepts a plan.
    state.pending_intent = {}; state.pending_id = "";
    current = [n.product_spec["type"] for n in items_of(p) if n.plannable()];
    if len(set(current + [n["type"] for n in proposal["needs"]])) > 6 { raise ValueError("Use at most six active needs."); }
    if proposal["intent"] == "plan" or proposal["needs"] { state.chat_planning = True; }
    if proposal["profile"] { shopping_operation(p, "update_profile", proposal["profile"], now); }
    for spec in proposal["needs"] {
        changes = dict(spec);
        changes["category"] = spec["type"]; changes["kind"] = "NEED";
        shopping_operation(p, "save_interest", changes, now);
        saved = [n for n in items_of(p) if n.product_spec.get("type") == spec["type"] and n.plannable()];
        if saved { spec["qty"] = saved[0].product_spec["qty"]; }
    }
    prefix = str(saved_message(proposal, lang));
    if proposal["address"] {
        state.chat_address_pending = True;
        state.address_candidates = [];
        try {
            workflow(p, "geocode", {"address": proposal["address"]}, now);
            found = state.address_candidates;
            if len(found) == 1 and found[0].get("precision") in ["building", "amenity"] and (found[0].get("confidence") or 0) >= 0.9 {
                workflow(p, "confirm_address", {"id": found[0]["id"]}, now);
                state.chat_address_pending = False;
                prefix += ("Saved starting address: ") + p.home_address + "\n";
            }
        } except ValueError as err {
            state.chat_question = question(conversation_context(p), "address", lang);
            return prefix + str(err) + "\n" + state.chat_question;
        }
    } elif proposal.get("address_choice") {
        idx = int(proposal["address_choice"]) - 1;
        if not state.chat_address_pending or idx >= len(state.address_candidates) { raise ValueError("This address selection is no longer available. Please type the address again."); }
        workflow(p, "confirm_address", {"id": state.address_candidates[idx]["id"]}, now);
        state.chat_address_pending = False;
        prefix += ("Saved starting address: ") + p.home_address + "\n";
    }
    # Ask once, when a many-variety item first joins the list. Any reply (or "any")
    # continues planning, and the item is no longer new, so it is not asked again.
    varied = [spec["type"] for spec in proposal["needs"] if spec["type"] not in current and needs_variety(spec)];
    if varied {
        state.chat_question = variety_question(varied);
        return prefix + state.chat_question;
    }
    if state.chat_address_pending {
        state.chat_question = question(conversation_context(p), "address", lang);
        return prefix + state.chat_question;
    }
    if state.chat_planning { return continue_plan(p, prefix); }
    if proposal["intent"] in ["search", "products", "refresh"] {
        action = "nearby" if proposal["intent"] == "search" else ("historical_prices" if proposal["intent"] == "products" else "refresh");
        result = shopping_operation(p, action, {"store": proposal.get("store_id", "")}, now);
        return prefix + str(result["message"]);
    }
    return prefix + (str(proposal["question"]) or ("Tell me your shopping needs, or ask me to generate a plan."));
}
