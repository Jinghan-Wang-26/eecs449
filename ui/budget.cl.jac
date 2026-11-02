"""Weekly budget and the spending ledger. Only user-reported amounts appear here."""

def:pub BudgetPanel(budget: dict, busy: bool, operate: any) -> JsxElement {
    has amount: str = "", store: str = "", category: str = "", spent_at: str = "", note: str = "",
        editing: str = "", edit_amount: str = "", request_id: str = crypto.randomUUID();

    def money(value: any) -> str {
        return "$" + Number(value).toFixed(2);
    }

    # Clear the form once the saved entry appears. A failed request keeps its
    # values and id, so retrying it cannot record the expense twice.
    can with (len([r for r in budget["entries"] if r["id"] == request_id])) entry {
        if len([r for r in budget["entries"] if r["id"] == request_id]) > 0 {
            amount = ""; note = ""; request_id = crypto.randomUUID();
        }
    }

    async def add(e: FormEvent) -> None {
        e.preventDefault();
        await operate("expense_add", {"id": request_id, "amount": amount, "store": store,
            "category": category, "spent_at": spent_at, "note": note});
    }

    has_budget = budget["weekly_budget"] > 0;
    used = 0 if not has_budget else Math.min(100, Math.round(budget["spent"] / budget["weekly_budget"] * 100));
    peak = 1;
    for w in budget["recent_weeks"] {
        if w["spent"] > peak { peak = w["spent"]; }
    }
    categories = Object.entries(budget["by_category"]);
    # The four-week chart only adds something once an earlier week has spending.
    history = len([w for w in budget["recent_weeks"].slice(0, -1) if w["spent"] > 0]) > 0;

    return <section className="budget-panel">
        <div className="budget-summary">
            <div><h3>This week</h3><p>{budget["week_start"] + " to " + budget["week_end"] + " (Monday to Sunday)"}</p></div>
            <div className="budget-figures">
                <div><span>Spent</span><strong>{money(budget["spent"])}</strong></div>
                <div><span>Budget</span><strong>{money(budget["weekly_budget"]) if has_budget else "Not set"}</strong></div>
                <div className={"over" if budget["over_budget"] else ""}><span>{"Over budget" if budget["over_budget"] else "Remaining"}</span><strong>{"—" if budget["remaining"] is None else money(Math.abs(budget["remaining"]))}</strong></div>
            </div>
            {if has_budget { <div className="budget-meter" role="progressbar" aria-label="Share of weekly budget spent" aria-valuemin="0" aria-valuemax="100" aria-valuenow={used}><span className={"over" if budget["over_budget"] else ""} style={{"width": str(used) + "%"}}></span></div> }}
            {if not has_budget { <p>Set a weekly budget under Preferences to see what is left.</p> }}
            <p>Counts what you recorded after shopping and expenses you add here. Plan estimates are not counted.</p>
        </div>

        {if len(categories) > 0 {
            <div className="budget-breakdown"><h3>By category</h3>
                {[<div key={pair[0]} className="budget-row"><span>{pair[0]}</span><span>{money(pair[1])}</span></div> for pair in categories]}
            </div>
        }}

        {if history {
            <div className="budget-weeks" aria-label="Spending in the last four weeks"><h3>Last four weeks</h3>
                <div className="week-bars">
                    {[<div key={w["week"]} className="week-bar"><span className="bar" style={{"height": str(Math.round(w["spent"] / peak * 100)) + "%"}}></span><strong>{money(w["spent"])}</strong><small>{"Week of " + w["start"].slice(5)}</small></div> for w in budget["recent_weeks"]]}
                </div>
            </div>
        }}

        <details className="quick-add"><summary>+ Record an expense</summary>
            <form onSubmit={add} className="profile-grid">
                <label>Amount paid ($)<input aria-label="Amount paid" type="number" min="0.01" max="10000" step="0.01" required value={amount} onChange={lambda e: ChangeEvent { amount = e.target.value; }} /></label>
                <label>Date<input aria-label="Purchase date" type="date" value={spent_at} onChange={lambda e: ChangeEvent { spent_at = e.target.value; }} /></label>
                <label>Store<input aria-label="Store" maxLength="80" value={store} placeholder="Optional" onChange={lambda e: ChangeEvent { store = e.target.value; }} /></label>
                <label>Item<input aria-label="Expense category" maxLength="40" value={category} placeholder="Optional" onChange={lambda e: ChangeEvent { category = e.target.value; }} /></label>
                <label>Note<input aria-label="Note" maxLength="200" value={note} onChange={lambda e: ChangeEvent { note = e.target.value; }} /></label>
                <button type="submit" disabled={busy}>Add expense</button>
            </form>
        </details>

        <h3>Ledger</h3>
        {if len(budget["entries"]) == 0 { <p>Nothing recorded yet. After a trip, record what you paid on the Shop step.</p> }}
        {[<div key={row["id"]} className={"ledger-row" + (" voided" if row["voided"] else "")}>
            <div>
                <span className="item-name">{money(row["amount"]) + " · " + (row["category"] or "uncategorized")}</span>
                <span className="item-meta">{row["spent_at"].slice(0, 10) + (" · " + row["store"] if row["store"] else "") + (" · from store visit" if row["source"] == "visit" else "") + (" · corrected" if len(row["history"]) > 0 else "") + (" · removed" + (": " + row["void_reason"] if row.get("void_reason") else "") if row["voided"] else "")}</span>
                {if row["note"] { <span className="item-meta">{row["note"]}</span> }}
                {if len(row["history"]) > 0 { <span className="item-meta">{"Previously " + [money(h["amount"]) for h in row["history"]].join(", ")}</span> }}
            </div>
            {if not row["voided"] and editing != row["id"] {
                <div className="row-actions">
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { editing = row["id"]; edit_amount = str(row["amount"]); }}>Correct</button>
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("expense_void", {"id": row["id"], "reason": "Removed by user"}); }}>Remove</button>
                </div>
            }}
            {if editing == row["id"] {
                <div className="row-actions">
                    <input aria-label="Corrected amount" type="number" min="0.01" step="0.01" value={edit_amount} onChange={lambda e: ChangeEvent { edit_amount = e.target.value; }} />
                    <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate("expense_correct", {"id": row["id"], "amount": edit_amount}); editing = ""; }}>Save</button>
                    <button type="button" onClick={lambda e: MouseEvent { editing = ""; }}>Cancel</button>
                </div>
            }}
        </div> for row in budget["entries"]]}
    </section>;
}
