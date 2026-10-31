"""Email delivery rules with the sender replaced; no messages leave the test."""
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.events { DeliveryState }
import from models.graph { Owns, owned }
import from server.shopping { shopping_operation }
import from notify.delivery { set_delivery, deliver_reminders, digest }
import from integrations.channels { ChannelError }

glob NOW: str = "2026-10-15T10:00:00-04:00",
     ADDRESS: str = "shopper@example.com",
     CONFIGURED: dict = {"email": True};

"""Two replenishment reminders become due at NOW."""
def shopper() -> UserProfile {
    p = UserProfile(transport=["WALK"], free_windows=["SAT 14:00-17:00"], weekly_budget=100);
    p +>:Owns:+> InterestPool();
    for item in ["milk", "eggs"] {
        shopping_operation(p, "save_interest", {"category": item, "kind": "REPLENISH",
            "replenishment_days": "7", "last_purchased_at": "2026-10-01"}, NOW);
    }
    return p;
}

def subscribed() -> UserProfile {
    p = shopper();
    with patch("notify.delivery.channel_status", return_value=CONFIGURED) {
        set_delivery(p, {"email": ADDRESS, "email_enabled": True});
    }
    return p;
}

def fails(f: any) -> bool {
    try { f(); } except ValueError { return True; }
    return False;
}

test "email is opt-in, validated and needs server settings" {
    p = shopper();
    with patch("notify.delivery.send_email") as sender {
        assert deliver_reminders(p, NOW) == "disabled";
        assert sender.call_count == 0;
    }
    with patch("notify.delivery.channel_status", return_value=CONFIGURED) {
        assert fails(lambda: set_delivery(p, {"email": "not-an-email", "email_enabled": True}));
        assert set_delivery(p, {"email": ADDRESS, "email_enabled": True}) == "Email settings saved.";
    }
    with patch("notify.delivery.channel_status", return_value={"email": False}) {
        assert fails(lambda: set_delivery(p, {"email": ADDRESS, "email_enabled": True}));
    }
}

test "new reminders are emailed once as one digest" {
    p = subscribed();
    with patch("notify.delivery.send_email") as sender {
        assert deliver_reminders(p, NOW) == 2;
        assert sender.call_count == 1;
        args = list(sender.call_args[0]);
        assert args[0] == ADDRESS and args[1] == "CartCompass: 2 reminders";
        assert "milk" in args[2] and "eggs" in args[2];
        assert deliver_reminders(p, "2026-10-15T10:05:00-04:00") == 0;
        assert sender.call_count == 1;
    }
    assert owned(p, DeliveryState).last_delivery["count"] == 2;
}

test "quiet hours send nothing" {
    p = subscribed();
    with patch("notify.delivery.send_email") as sender {
        assert deliver_reminders(p, "2026-10-15T23:30:00-04:00") == 0;
        assert sender.call_count == 0;
    }
}

test "failures back off and retry the same reminders" {
    p = subscribed();
    with patch("notify.delivery.send_email", side_effect=ChannelError("Email delivery failed: TimeoutError.")) {
        assert deliver_reminders(p, NOW).startswith("error:");
    }
    state = owned(p, DeliveryState);
    assert state.failure["count"] == 1 and state.failure["next_retry_at"] == "2026-10-15T10:05:00-04:00";
    with patch("notify.delivery.send_email") as sender {
        assert deliver_reminders(p, "2026-10-15T10:02:00-04:00") == "waiting to retry";
        assert sender.call_count == 0;
    }
    with patch("notify.delivery.send_email", side_effect=ChannelError("again")) {
        deliver_reminders(p, "2026-10-15T10:05:00-04:00");
    }
    assert state.failure["count"] == 2 and state.failure["next_retry_at"] == "2026-10-15T10:15:00-04:00";
    with patch("notify.delivery.send_email") {
        assert deliver_reminders(p, "2026-10-15T10:15:00-04:00") == 2;
    }
    assert state.failure == {};
}

test "changing the address forgets old receipts" {
    p = subscribed();
    with patch("notify.delivery.send_email") {
        deliver_reminders(p, NOW);
    }
    with patch("notify.delivery.channel_status", return_value=CONFIGURED) {
        set_delivery(p, {"email": "other@example.com"});
    }
    with patch("notify.delivery.send_email") as sender {
        assert deliver_reminders(p, "2026-10-15T10:01:00-04:00") == 2;
        assert sender.call_args[0][0] == "other@example.com";
    }
}

test "long digests are truncated" {
    cards = [{"key": str(i), "kind": "REPLENISH", "message": f"Item {i}"} for i in range(7)];
    message = digest(cards);
    assert message["title"] == "CartCompass: 7 reminders";
    assert "Item 4" in message["body"] and "Item 5" not in message["body"] and "2 more" in message["body"];
    assert digest(cards[:1])["title"] == "CartCompass reminder";
}

test "panel actions save settings and send a test email" {
    p = shopper();
    with patch("notify.delivery.channel_status", return_value=CONFIGURED) {
        out = shopping_operation(p, "notify_settings", {"email": ADDRESS, "email_enabled": True}, NOW);
    }
    assert out["message"] == "Email settings saved." and out["delivery"]["email_enabled"];
    with patch("notify.delivery.send_email") as sender {
        out = shopping_operation(p, "notify_test", {}, NOW);
        assert out["message"] == "Test email sent." and sender.call_count == 1;
    }
}
