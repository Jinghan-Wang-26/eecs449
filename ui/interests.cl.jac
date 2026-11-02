"""Suggestions from the shopper's interests: sales on things they buy, items they usually
restock by now, and due reminders. Nothing is added until the shopper says yes."""

def card_of(item: dict) -> any {
    kind = item["kind"];
    if kind == "SALE" { return {"type": "watch", "icon": "%", "title": "On sale", "skip": "dismiss", "skip_label": "No thanks"}; }
    if kind in ["USUAL", "REPLENISH"] { return {"type": "rep", "icon": "↻", "title": "Time to restock", "skip": "snooze", "skip_label": "Not now"}; }
    if kind == "PRICE_DROP" { return {"type": "watch", "icon": "◎", "title": "Price drop", "skip": "snooze", "skip_label": "Not now"}; }
    if kind == "RESTOCK" { return {"type": "watch", "icon": "◎", "title": "Back in stock", "skip": "snooze", "skip_label": "Not now"}; }
    return None;
}

def:pub InterestStrip(snapshot: dict, busy: bool, operate: any) -> JsxElement {
    cards = [];
    for item in snapshot.get("reminders", []) {
        look = card_of(item);
        if look { cards.append(Object.assign({"key": item["key"], "text": item["message"], "action": "reminder"}, look)); }
    }
    for item in snapshot.get("discoveries", []) {
        cards.append({"key": item["key"], "type": "disc", "icon": "✦", "title": item["name"], "text": item["reason"], "action": "discovery", "skip": "dismiss", "skip_label": "No thanks"});
    }
    if len(cards) == 0 {
        return <p id="interests" className="interests-empty">Sales on things you buy and restock reminders show up here after you record a couple of purchases.</p>;
    }
    return <section id="interests" className="interests" aria-label="From your interests">
        <div className="interests-head"><span><b>From your interests</b>{" · " + str(len(cards)) + (" suggestion" if len(cards) == 1 else " suggestions")}</span></div>
        <div className="interest-cards">{[<div key={card["key"]} className="interest-card">
            <span className={"ic " + card["type"]} aria-hidden="true">{card["icon"]}</span>
            <b>{card["title"]}</b>
            <small>{card["text"]}</small>
            <div className="row-actions">
                <button type="button" disabled={busy} onClick={lambda e: MouseEvent { operate(card["action"], {"key": card["key"], "action": "accept" if card["action"] == "discovery" else "add"}); }}>Add to list</button>
                <button type="button" className="ghost" disabled={busy} onClick={lambda e: MouseEvent { operate(card["action"], {"key": card["key"], "action": card["skip"]}); }}>{card["skip_label"]}</button>
            </div>
        </div> for card in cards]}</div>
    </section>;
}
