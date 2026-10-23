impl ShoppingPanel.operate(action: str, data: dict) -> None {
    if busy { return; }
    busy = True;
    try {
        result = root spawn ShoppingAction(action=action, data=data);
        if not result.reports or len(result.reports) == 0 {
            notice = "No response from shopping tools.";
        } else {
            payload = result.reports[0];
            if payload["error"] {
                notice = payload["error"];
            } else {
                snapshot = payload;
                notice = payload["message"] or ("Checked " + payload["checked_at"]);
            }
        }
    } except Exception as err {
        notice = "Shopping request failed: " + str(err);
    }
    busy = False;
}

impl ShoppingPanel.save(e: FormEvent) -> None {
    e.preventDefault();
    await operate("save_interest", {"category": category, "kind": kind, "qty": quantity,
        "target_price": target if kind == "WATCH" else "0",
        "replenishment_days": days if kind == "REPLENISH" else "0",
        "last_purchased_at": purchased if kind == "REPLENISH" else ""});
}
