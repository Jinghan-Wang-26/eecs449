"""Server calls for the shopping panel. `operate` reports success so multi-step
flows (recording several purchases) can stop at the first failure."""

impl ShoppingPanel.operate(action: str, data: dict, source: str = "") -> bool {
    if busy { return False; }
    busy = True;
    ok = False;
    try {
        result = root spawn ShoppingAction(action=action, data=data);
        if not result.reports or len(result.reports) == 0 {
            notice = "No response from shopping tools.";
        } else {
            payload = result.reports[0];
            if payload["error"] {
                notice = payload["error"];
                error_notice = payload["error"];
            } else {
                error_notice = "";
                # Tell the chat what its reply changed, so it can show a change card.
                if source == "chat" and snapshot.get("workspace") {
                    changes = describe_changes(snapshot, payload);
                    if len(changes) > 0 {
                        window.dispatchEvent(new(CustomEvent, "workspace-changed", {"detail": changes}));
                    }
                }
                snapshot = payload;
                notice = payload["message"] or ("Checked " + payload["checked_at"]);
                ok = True;
            }
        }
    } except Exception as err {
        failure = "Shopping request failed: " + str(err);
        notice = failure;
        error_notice = failure;
    }
    busy = False;
    return ok;
}

impl ShoppingPanel.save(e: FormEvent) -> None {
    e.preventDefault();
    ok = await operate("save_interest", {"category": category.strip().lower(), "kind": "NEED", "qty": quantity,
        "target_price": "0", "replenishment_days": "0", "last_purchased_at": ""});
    if ok { category = ""; quantity = "1"; }
}
