"""Manual merchant checkout evidence; never presented as an API quote or an order."""
def:pub DeliveryQuotes(workspace: dict, busy: bool, operate: any) -> JsxElement {
    has values: dict = {'merchant':'','source_url':'','window_start':'','window_end':'','address_confirmed':False,'items_confirmed':False,'fees_confirmed':False}, selected: dict = {};
    def change(field: str, value: any) -> None {
        next_values = JSON.parse(JSON.stringify(values)); next_values[field] = value; values = next_values;
    }
    def local_time(value: str) -> str {
        if not value { return ''; }
        date = window.Reflect.construct(window.Date,[value]);
        return window.Reflect.construct(window.Date,[date.getTime()-date.getTimezoneOffset()*60000]).toISOString().slice(0,16);
    }
    def save_time(field: str, value: str) -> None {
        change(field,window.Reflect.construct(window.Date,[value]).toISOString() if value else '');
    }
    async def save(e: FormEvent) -> None {
        e.preventDefault();
        data = JSON.parse(JSON.stringify(values));
        data['categories'] = [n['type'] for n in workspace.get('shopping_needs',[]) if selected.get(n['type'],False)];
        await operate('save_delivery_quote',data);
    }
    def edit(quote: dict) -> None {
        next_values = JSON.parse(JSON.stringify(quote['fees']));
        for key in ['merchant','source_url','window_start','window_end'] { next_values[key] = quote[key]; }
        next_values['replace_id'] = quote['id'];
        next_values['address_confirmed'] = False; next_values['items_confirmed'] = False; next_values['fees_confirmed'] = False;
        next_selected = {};
        for category in quote['categories'] { next_selected[category] = True; }
        values = next_values; selected = next_selected;
    }
    return <section className="delivery-quotes" aria-label="Delivery checkout quotes">
        <h3>Compare a delivery checkout quote</h3>
        <p>Enter a quote from merchant checkout for your confirmed address. This is user-entered evidence, not an API-verified price or an order. Keep the selected basket intact; fees may change if you edit it.</p>
        <details><summary>Add or update a delivery quote</summary>
            <form className="profile-grid" onSubmit={save}>
                <label>Merchant<input aria-label="Delivery merchant" value={values.get('merchant','')} onChange={lambda e: ChangeEvent { change('merchant',e.target.value); }} /></label>
                <label>Public merchant URL<input aria-label="Delivery source URL" type="url" placeholder="https://www.kroger.com/" value={values.get('source_url','')} onChange={lambda e: ChangeEvent { change('source_url',e.target.value); }} /></label>
                {[<label key={field[0]}>{field[1]}<input aria-label={field[1]} type="number" min="0" step="0.01" placeholder="Unknown" value={values.get(field[0],'') if values.get(field[0],None) is not None else ''} onChange={lambda e: ChangeEvent { change(field[0],e.target.value); }} /></label> for field in [['merchandise','Delivery merchandise subtotal (USD)'],['delivery_fee','Delivery fee (USD)'],['service_fee','Service fee (USD)'],['other_fee','Other fees (USD)'],['tax','Checkout tax (USD)'],['tip','Tip (USD)'],['discount','Applied checkout discount (USD)'],['minimum_order','Minimum order (USD)']]]}
                <label>Delivery window starts<input aria-label="Delivery window start" type="datetime-local" value={local_time(values.get('window_start',''))} onChange={lambda e: ChangeEvent { save_time('window_start',e.target.value); }} /></label>
                <label>Delivery window ends<input aria-label="Delivery window end" type="datetime-local" value={local_time(values.get('window_end',''))} onChange={lambda e: ChangeEvent { save_time('window_end',e.target.value); }} /></label>
                <p>Delivery times use your browser's local timezone. Leave unknown amounts blank; enter 0 only when checkout confirms no charge. Quotes expire after 30 minutes or when the delivery window begins, whichever comes first.</p>
                <fieldset><legend>Exact basket covered by this quote</legend>
                    {[<label key={n['type']}><input type="checkbox" aria-label={'Deliver '+n['type']} checked={selected.get(n['type'],False)} onChange={lambda e: ChangeEvent { next_selected = JSON.parse(JSON.stringify(selected)); next_selected[n['type']] = e.target.checked; selected = next_selected; }} />{str(n['qty'])+' × '+n['type']+' · '+n.get('brand','')+' '+n.get('size','')}</label> for n in workspace.get('shopping_needs',[])]}
                </fieldset>
                <label><input type="checkbox" aria-label="Checkout serves my confirmed address" checked={values.get('address_confirmed',False)} onChange={lambda e: ChangeEvent { change('address_confirmed',e.target.checked); }} />Checkout serves my currently confirmed address.</label>
                <label><input type="checkbox" aria-label="Checkout basket matches selected needs" checked={values.get('items_confirmed',False)} onChange={lambda e: ChangeEvent { change('items_confirmed',e.target.checked); }} />The checkout basket contains exactly these quantities and products, meets my brand, size and dietary requirements, and is available for the selected slot.</label>
                <label><input type="checkbox" aria-label="All checkout fees confirmed" checked={values.get('fees_confirmed',False)} onChange={lambda e: ChangeEvent { change('fees_confirmed',e.target.checked); }} />All checkout charges, discounts and the minimum order are included above.</label>
                <button type="submit" disabled={busy}>{'Replace delivery quote' if values.get('replace_id') else 'Save delivery quote'}</button>
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { values = {}; selected = {}; }}>Clear quote form</button>
            </form>
        </details>
        {[<article className="result-card" key={q['id']}>
            <strong>{q['merchant']+' · USER-ENTERED CHECKOUT QUOTE'}</strong>
            <p>{q['categories'].join(', ')+' · Total: '+('USD '+str(q['total']) if q['total'] is not None else 'Unknown — complete all fees')}</p>
            <p>{'Entered '+q['entered_at']+' · Expires '+q['valid_until']}</p>
            <p>{'Delivery: '+q['window_start']+' → '+q['window_end']}</p>
            <a href={q['source_url']} target="_blank" rel="noreferrer">Merchant source</a>
            <button disabled={busy} onClick={lambda e: MouseEvent { edit(q); }}>Update from checkout</button>
            <button disabled={busy} onClick={lambda e: MouseEvent { operate('remove_delivery_quote',{'id':q['id']}); }}>Remove quote</button>
        </article> for q in workspace.get('delivery_quotes',[])]}
    </section>;
}
