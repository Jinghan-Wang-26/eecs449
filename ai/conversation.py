"""Grounded follow-up questions and summaries; no fabricated shopping facts."""
import re


def language(text, previous="en") -> str:
    if re.search(r"[\u4e00-\u9fff]", text): return "zh"
    if re.search(r"[a-zA-Z]{2,}", text): return "en"
    return previous


def missing_fields(context) -> list:
    missing=[]
    if context["data_mode"] == "live" and (context.get("address_pending") or not context["has_confirmed_address"]): missing.append("address")
    if not context["needs"]: missing.append("needs")
    modes=context["transport"]
    if not modes or (context["data_mode"] == "live" and not set(modes) & {"WALK","BIKE","CAR"}): missing.append("transport")
    if not context.get("free_windows"): missing.append("free_windows")
    if context["data_mode"] == "mock" and context["budget"] <= 0: missing.append("weekly_budget")
    return missing


def question(context, field, lang) -> str:
    zh=lang == "zh"
    if field == "address":
        candidates=context.get("address_candidates", []) if context.get("address_pending") else []
        if candidates:
            title="请确认用于出发的地址，直接回复编号（或重新输入地址）：" if zh else "Which starting address should I use? Reply with its number, or type a different address:"
            return title+"\n"+"\n".join(f"{i+1}. {c['address']}" for i,c in enumerate(candidates))
        return "从哪里出发购物？请在聊天里告诉我地址、城市和邮编。" if zh else "Where will you start shopping? Tell me your address, city and ZIP code here."
    messages={
        "needs": ("这次想买什么、各买几包？直接在聊天里告诉我，例如牛奶两包、米一包。", "What would you like to buy, and how many packages of each? Tell me here, for example two milk and one rice."),
        "transport": ("你目前的出行方式无法生成可验证路线。当前支持步行、骑车或开车；你可以使用哪一种？如果只能坐公交，请告诉我，我会保留这个限制。", "Your saved transport cannot produce a verified route. Can you walk, cycle or drive? If bus is your only option, tell me; I will keep that constraint."),
        "free_windows": ("你哪天、几点到几点有空购物？例如周六下午2点到5点，直接回复即可。", "What day and time range are you free to shop? For example, Saturday 2–5 pm. Reply here."),
        "weekly_budget": ("你的购物预算是多少美元？", "What is your shopping budget in dollars?")}
    return messages[field][0 if zh else 1]


def saved_message(proposal, lang) -> str:
    parts=[]
    if proposal["profile"]:
        labels={"weekly_budget":"预算", "free_windows":"空闲时间", "transport":"出行方式", "max_walk_min":"最长步行分钟", "carry_limit_kg":"携带上限kg"}
        parts.extend(f"{labels.get(k,k) if lang=='zh' else k}: {v}" for k,v in proposal["profile"].items())
    parts.extend(f"{n['qty']} × {n['type']}" for n in proposal["needs"])
    return (("已更新上方信息：" if lang=="zh" else "Updated your shopping information: ")+"; ".join(parts)+".\n") if parts else ""


def plan_summary(workspace, lang) -> str:
    zh=lang=="zh"
    plans=[p for p in workspace["visit_plans"] if p["status"]=="PROPOSED"]
    if not plans:
        return "\n".join(workspace.get("notices", [])) or ("没有找到附近门店，可以扩大搜索半径或更换出发地址。" if zh else "No nearby stores were found. Try a wider radius or another starting address.")
    eligible=sum(bool(p["accept_allowed"]) for p in plans)
    lines=[f"已生成 {len(plans)} 个门店候选，其中 {eligible} 个可以查看并接受：" if zh else f"Found {len(plans)} store options; {eligible} can be reviewed and accepted:"]
    for i,p in enumerate(plans):
        items=", ".join(f"{x['qty']} × {x['category']}" for x in p["items"])
        lines.append(f"{i+1}. {p['store']['name']} — {p['store']['address']}\n   {items}")
        if p["route"]:
            t=p["route"]
            lines.append(f"   {t['mode']}: {t['min']} min round trip + {t['shopping_min']} min shopping; {t['window'] or 'no fitting time window'}")
        lines.append((f"   历史记录匹配 {p['matched']}/{p['need_count']} 项；" if zh else f"   Historical matches: {p['matched']}/{p['need_count']}; ")+(f"USD {p['reference_subtotal']} historical reference (not today's total)" if p['reference_subtotal'] is not None else "price unknown"))
        if p["blockers"]: lines.append("   "+"; ".join(p["blockers"]+p["route_notices"]))
    lines.append("当前价格、库存和营业时间未知。未匹配到历史记录不代表没货。请在上方门店计划中查看证据并选择接受。" if zh else "Current prices, stock and opening hours remain unknown. Missing historical evidence does not mean out of stock. Review evidence and accept a visit in the shopping panel.")
    if not eligible:
        lines.append("这些方案暂时不能接受；请在聊天里告诉我可以调整哪些出行、时间或携带限制，我会重新生成。" if zh else "These options are blocked. Tell me which travel, time or carrying constraints you can change, and I will rebuild the plan.")
    return "\n".join(lines)
