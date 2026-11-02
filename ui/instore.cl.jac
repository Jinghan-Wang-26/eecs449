"""Shop stage. Picking an item only marks it as in the basket (kept in this browser);
nothing reaches the budget until the shopper records what they actually paid."""
import from .planview { money, kg, item_amount, delivered_items, carried, tally, tally_label }

def:pub InStore(plan: dict, picked: dict, toggle: any, busy: bool, operate: any, finished: any) -> JsxElement {
    has recording: bool = False, rows: dict = {}, saving: bool = False, problem: str = "";
    weights = {};
    for row in carried(plan) { weights[row["name"]] = row["kg"]; }
    pending = [item for item in plan["items"] if item["outcome"] == "PENDING"];
    shelf = [item for item in pending if item.get("fulfillment", None) != "DELIVERY"];
    done = [item for item in plan["items"] if item["outcome"] != "PENDING"];
    delivered = delivered_items(plan);

    def is_picked(item: dict) -> bool { return picked.get(plan["key"] + "|" + item["category"], False); }

    def tax_text(item: dict) -> str {
        tax = item.get("tax_amount", None);
        if tax is None { return " · tax not estimated"; }
        return " + tax " + money(tax) if tax > 0 else " · no sales tax (groceries)";
    }

    """Listed price plus estimated tax for all requested packages; None for delivery or unpriced items."""
    def estimate_of(item: dict) -> any {
        amount = item_amount(item);
        if item.get("fulfillment", None) == "DELIVERY" or amount is None { return None; }
        return amount + (item.get("tax_amount", None) or 0);
    }

    """Estimate for a bought package count, as the text the amount field shows."""
    def estimate_text(item: dict, qty: str) -> str {
        value = estimate_of(item);
        if value is None or Number(qty) < 1 { return ""; }
        return Number(value * Math.min(Number(qty), item["qty"]) / item["qty"]).toFixed(2);
    }

    def row_of(item: dict) -> dict {
        saved = rows.get(item["category"], None);
        if saved { return saved; }
        # Unticked items wait to be recorded; "not found" is only what the shopper says.
        # Amounts start as estimates (est) and become receipt amounts once typed over.
        if item.get("fulfillment", None) == "DELIVERY" { return {"result": "LATER", "qty": str(item["qty"]), "paid": "", "est": False}; }
        guess = estimate_text(item, str(item["qty"]));
        return {"result": "BOUGHT" if is_picked(item) else "LATER", "qty": str(item["qty"]), "paid": guess, "est": guess != ""};
    }

    def counts() -> dict {
        out = {"bought": 0, "unpaid": 0, "later": 0, "other": 0, "est": 0};
        for item in pending {
            r = row_of(item);
            if r["result"] == "BOUGHT" { out["bought"] += 1; if r["paid"] == "" { out["unpaid"] += 1; } elif r["est"] { out["est"] += 1; } }
            elif r["result"] == "LATER" { out["later"] += 1; }
            else { out["other"] += 1; }
        }
        return out;
    }

    def set_row(item: dict, field: str, value: str) -> None {
        updated = JSON.parse(JSON.stringify(rows));
        current = row_of(item);
        current[field] = value;
        if field == "paid" { current["est"] = False; }
        # An untouched estimate follows the package count; a typed receipt amount never changes.
        if field == "qty" and current["est"] { current["paid"] = estimate_text(item, value); }
        updated[item["category"]] = current;
        rows = updated;
    }

    def paid_total() -> float {
        total = 0;
        for item in pending {
            r = row_of(item);
            if r["result"] == "BOUGHT" and r["paid"] != "" { total += Number(r["paid"]); }
        }
        return total;
    }

    async def save_all() -> None {
        saving = True; problem = "";
        saved = 0; paid = 0; bought = 0;
        for item in pending {
            r = row_of(item);
            if r["result"] == "LATER" { continue; }
            data = {"key": plan["key"], "action": "outcome", "category": item["category"]};
            if r["result"] == "BOUGHT" and Number(r["qty"]) >= 1 {
                count = Math.min(Number(r["qty"]), item["qty"]);
                data["outcome"] = "PURCHASED" if count == item["qty"] else "PARTIAL";
                data["bought_qty"] = str(count);
                data["actual_paid"] = r["paid"];
                data["paid_estimated"] = r["est"] and r["paid"] != "";
                if r["paid"] != "" { paid += Number(r["paid"]); }
                bought += 1;
            } elif r["result"] == "SKIPPED" {
                data["outcome"] = "SKIPPED";
            } else {
                data["outcome"] = "NOT_FOUND";
            }
            ok = await operate("visit_action", data);
            if not ok {
                problem = "Saved " + str(saved) + " items. " + item["category"] + " was not saved; fix it and save again. Saved items will not be recorded twice.";
                saving = False;
                return;
            }
            saved += 1;
        }
        saving = False; recording = False;
        finished({"store": plan["store"]["name"], "count": saved, "bought": bought, "paid": paid, "plan": plan["key"]});
    }

    in_basket = [item for item in shelf if is_picked(item)];
    picked_count = len(in_basket);
    basket = tally([item_amount(item) for item in in_basket]);
    summary = counts();

    if recording {
        return <section aria-label="Record what you paid">
            <div className="stage-head"><h3>{"What did you pay at " + plan["store"]["name"] + "?"}</h3><button className="ghost" onClick={lambda e: MouseEvent { recording = False; }}>Back to list</button></div>
            <div className="record-table">
                <div className="record-row head"><span>Item</span><span>Packages</span><span>Paid ($)</span><span>Result</span></div>
                {[<div key={item["category"]} className={"record-row" + ("" if row_of(item)["result"] == "BOUGHT" else " skip")}>
                    <span><b>{item["category"]}</b><br /><small>{("delivery · price is in the checkout total" if item.get("fulfillment", None) == "DELIVERY" else "listed " + money(item_amount(item)) + tax_text(item)) + " · " + str(item["qty"]) + " needed"}</small></span>
                    <input type="number" min="1" max={str(item["qty"])} step="1" aria-label={"Packages bought: " + item["category"]} disabled={row_of(item)["result"] != "BOUGHT"} value={row_of(item)["qty"]} onChange={lambda e: ChangeEvent { set_row(item, "qty", e.target.value); }} />
                    <input type="number" min="0" step="0.01" aria-label={"Actual amount paid: " + item["category"]} disabled={row_of(item)["result"] != "BOUGHT"} className={"est" if row_of(item)["est"] else ""} title={"Estimate: listed price plus tax. Type your receipt amount to replace it." if row_of(item)["est"] else ""} value={row_of(item)["paid"]} placeholder="from receipt" onChange={lambda e: ChangeEvent { set_row(item, "paid", e.target.value); }} />
                    <select className="skip-toggle" aria-label={"Result for " + item["category"]} value={row_of(item)["result"]} onChange={lambda e: ChangeEvent { set_row(item, "result", e.target.value); }}>
                        <option value="LATER">Record later</option><option value="BOUGHT">{"Received" if item.get("fulfillment", None) == "DELIVERY" else "Bought"}</option><option value="NOT_FOUND">{"Not received" if item.get("fulfillment", None) == "DELIVERY" else "Not found"}</option><option value="SKIPPED">Skipped</option>
                    </select>
                </div> for item in pending]}
                <div className="record-total"><span>{"Total you paid" + (" · " + str(summary["est"]) + " estimated" if summary["est"] > 0 else "")}</span><span className="num">{money(paid_total())}</span></div>
            </div>
            <div className="info-box"><b>Check against your receipt.</b> Grey italic amounts are estimates: the listed regular price plus estimated tax, without sale or loyalty discounts. Type over any that differ. Estimates you keep are saved as estimates and can be corrected later in Budget. Fewer packages saves the item as partly bought and the rest stays on your list. Not found and "record later" items stay on your list.</div>
            {if problem { <p role="alert">{problem}</p> }}
            <div className="cta-row"><span>{"Saves " + str(summary["bought"]) + " bought · " + money(paid_total()) + " to this week's budget" + ((" (" + str(summary["est"]) + " estimated)") if summary["est"] > 0 else "") + ((" · " + str(summary["unpaid"]) + " without an amount") if summary["unpaid"] > 0 else "") + ((" · " + str(summary["later"]) + " left for later") if summary["later"] > 0 else "") + "."}</span><button className="go cta" disabled={busy or saving or summary["bought"] + summary["other"] == 0} onClick={lambda e: MouseEvent { save_all(); }}>{"Saving…" if saving else "Save purchases"}</button></div>
        </section>;
    }

    return <section aria-label="Shopping list for this visit">
        <div className="stage-head"><h3>{"At " + plan["store"]["name"]}</h3><small>{str(picked_count) + " of " + str(len(shelf)) + " in your basket"}</small></div>
        {if len(shelf) > 0 {
            <div className="store-list">{[<div key={item["category"]} className={"store-item" + (" picked" if is_picked(item) else "")}>
                <button type="button" className="pick" aria-pressed={is_picked(item)} aria-label={("Put back " if is_picked(item) else "Put in basket: ") + item["category"]} onClick={lambda e: MouseEvent { toggle(plan["key"] + "|" + item["category"]); }}>{"✓" if is_picked(item) else ""}</button>
                <span><b>{str(item["qty"]) + " × " + item["category"]}</b><small>{"Listed " + money(item_amount(item)) + ((" · " + kg(weights.get(item["category"], None))) if weights.get(item["category"], None) is not None else "") + ((" · " + item["quote"]["availability"].replace("_", " ").lower()) if item.get("quote", None) else "")}</small></span>
                <span className="in-basket">{"in basket" if is_picked(item) else ""}</span>
            </div> for item in shelf]}</div>
        }}
        {if len(done) > 0 {
            <p>{"Already recorded: " + [item["category"] + " (" + item["outcome"].replace("_", " ").lower() + ")" for item in done].join(", ")}</p>
        }}
        {if len(delivered) > 0 and plan.get("delivery_quote", None) {
            <div className="delivery-box"><b>{[item["category"] for item in delivered].join(", ") + " · delivery"}</b><span>CartCompass does not place orders. Order it yourself on the merchant site before the quote changes.</span>
                <a href={plan["delivery_quote"]["source_url"]} target="_blank" rel="noreferrer">{"Open " + plan["delivery_quote"]["merchant"] + " ↗"}</a></div>
        }}
        <div className="cta-row"><span>{"Basket estimate " + tally_label(basket, money) + " · nothing goes into your budget until you record what you paid."}</span>
            <button className="primary cta" disabled={len(pending) == 0} onClick={lambda e: MouseEvent { recording = True; }}>{"Checked out? Record purchase" if len(shelf) > 0 else "Record delivery"}</button></div>
        <button className="ghost" disabled={busy} onClick={lambda e: MouseEvent { operate("visit_action", {"key": plan["key"], "action": "cancel"}); }}>Cancel this visit</button>
    </section>;
}

def:pub TripComplete(summary: dict, budget: any, plan: any, busy: bool, operate: any, open_budget: any) -> JsxElement {
    remaining = [item for item in (plan["items"] if plan else []) if item.get("remaining_qty", 0) > 0 or item["outcome"] in ["NOT_FOUND", "SKIPPED"]];
    return <section className="done-card" aria-label="Trip recorded">
        <h3><i aria-hidden="true">✓</i>Trip recorded</h3>
        <span>{str(summary["bought"]) + " bought" + ((" · " + str(summary["count"] - summary["bought"]) + " not found or skipped") if summary["count"] > summary["bought"] else "") + " at " + summary["store"] + " · you reported paying "}<b>{money(summary["paid"])}</b></span>
        {if budget and budget["weekly_budget"] > 0 { <span><b id="chg-left" className="hl">{money(budget["remaining"])}</b>{" left this week"}</span> }}
        {if len(remaining) > 0 { <span className="todo">{"Still needed: " + [item["category"] for item in remaining].join(", ")}</span> }}
        {if plan and plan.get("delivery_quote", None) { <span className="todo">Delivery payment not recorded yet. Add it in Budget when you are charged.</span> }}
        <div className="cta-row">
            <button onClick={lambda e: MouseEvent { open_budget(); }}>View budget</button>
            {if len(remaining) > 0 { <button className="primary" disabled={busy} onClick={lambda e: MouseEvent { operate("recommend_visits", {}); }}>Plan the remaining items</button> }}
        </div>
    </section>;
}
