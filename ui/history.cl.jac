"""Historical store price evidence kept separate from current shopping quotes."""
def:pub HistoricalPrices(data: dict, busy: bool, operate: any) -> JsxElement {
    has filter: str = "";
    return <section id="historical-price-results">
        <h3>{"Historical prices · " + data["store_name"]}</h3>
        <p>Community observations, not current offers or inventory. Prices may have changed. Discount conditions and price units must be checked in the linked evidence.</p>
        <p>{str(data["total"]) + " records · Page " + str(data["page"]) + " of " + str(data["pages"])}</p>
        <button disabled={busy or data["page"] <= 1} onClick={lambda e: MouseEvent { operate("historical_prices", {"store": data["store_key"], "page": data["page"] - 1}); }}>Previous records</button>
        <button disabled={busy or data["page"] >= data["pages"] or data["page"] >= 100} onClick={lambda e: MouseEvent { operate("historical_prices", {"store": data["store_key"], "page": data["page"] + 1}); }}>Next records</button>
        <label>Filter this page<input aria-label="Filter price records on this page" value={filter} onChange={lambda e: ChangeEvent { filter = e.target.value; }} /></label>
        {if len(data["records"]) == 0 { <p>No usable price records on this page. This does not confirm absence of products in the store.</p> }}
        {[<article className="result-card" key={str(row["record_id"])}>
            <strong>{row["name"]}</strong>
            <p>{row["brand"] + " · " + row["size_label"]}</p>
            <p>{row["currency"] + " " + str(row["price"]) + " · Recorded " + row["recorded_on"] + " · Unit: " + row["price_per"]}</p>
            {if row["discounted"] { <p>{"Discounted observation · Conditions: " + (row["discount_type"] or "unspecified")}</p> }}
            <p>Current price: unknown · Current inventory: unknown</p>
            <a href={row["source_url"]} target="_blank" rel="noreferrer">View price record</a> · <a href={row["proof_url"]} target="_blank" rel="noreferrer">View supporting evidence</a>
        </article> for row in data["records"] if filter.lower() in row["name"].lower()]}
        <p>Data: <a href="https://prices.openfoodfacts.org/" target="_blank" rel="noreferrer">Open Prices / Open Food Facts</a> · <a href="https://opendatacommons.org/licenses/odbl/1-0/" target="_blank" rel="noreferrer">ODbL</a>. These historical observations are excluded from current-price planning.</p>
    </section>;
}
