"""Native-Jac runtime boundaries and regressions found during conversion."""
import importlib;
import from pathlib { Path }
import from unittest.mock { patch }
import from urllib.error { URLError }
import app_settings;
import from app_settings { quiet }
import from planning { tax }
import from integrations { providers, transit }


test "application modules load from Jac with no Python runtime duplicates" {
    names = ["app_settings", "ai.codex_local", "ai.explanations", "ai.intents", "ai.matching",
        "integrations.channels", "integrations.coverage", "integrations.http_transport",
        "integrations.itineraries", "integrations.openprices", "integrations.providers",
        "integrations.retail", "integrations.transit", "planning.comparisons", "planning.tax",
        "planning.visits", "interests.suggest", "providers.demo_clock"];
    for name in names {
        module = importlib.import_module(name);
        source = Path(module.__file__);
        assert source.suffix == ".jac", name;
        assert not source.with_suffix(".py").exists(), name;
        assert "::py::" not in source.read_text(), name;
    }
    project = Path(app_settings.__file__).parent;
    for directory in ["ai", "integrations", "planning", "providers", "interests", "server", "models", "notify", "budget", "feedback", "harness", "sync", "ui"] {
        assert not `list((project / directory).rglob("*.py")), directory;
    }
}

test "quiet hour boundaries preserve nested conditional meaning" {
    base = {"timezone": "America/New_York", "quiet_hours_start": 22, "quiet_hours_end": 8};
    assert quiet("2026-11-14T23:00:00-05:00", base);
    assert quiet("2026-11-14T07:59:00-05:00", base);
    assert not quiet("2026-11-14T08:00:00-05:00", base);
    assert not quiet("2026-11-14T21:59:00-05:00", base);
    for hour in [0, 7, 12, 23] {
        assert not quiet(f"2026-11-14T{hour:02d}:00:00-05:00", {**base, "quiet_hours_start": 8, "quiet_hours_end": 8});
    }
    assert quiet("2026-11-14T12:00:00-05:00", {**base, "quiet_hours_start": 9, "quiet_hours_end": 17});
}

test "both taxable and grocery rates multiply the item amount" {
    # Synthetic rates exercise both branches without claiming a real tax rule.
    rule = {"name": "Synthetic", "rate": 0.06, "food_rate": 0.02, "note": "Test only"};
    with patch.dict(tax.STATE_RULES, {"ZZ": rule}) {
        items = [{"category": "milk", "current_amount": 10}, {"category": "soap", "current_amount": 20}];
        result = tax.estimate(items, ["Synthetic store, ZZ 00000"], None);
        assert items[0]["tax_amount"] == 0.2;
        assert items[1]["tax_amount"] == 1.2;
        assert result["tax"] == 1.4;
    }
}

test "provider transport failures keep the public error and suppress raw causes" {
    with patch.object(providers, "urlopen", side_effect=URLError("synthetic-private-query")) {
        failed = False;
        try { providers.request_json("https://example.invalid/public-test"); }
        except providers.ProviderError as error {
            failed = True;
            assert "synthetic-private-query" not in str(error);
            assert error.__suppress_context__;
        }
        assert failed;
    }
}

test "unverified transfer removal remains a dictionary operation" {
    links = {"A": {"B": {"verified": False}}};
    feed = {"stops": {"A": {"lat": 42.28, "lon": -83.74}, "B": {"lat": 42.281, "lon": -83.74}}};
    journeys = [{"legs": [{"transfer_from": "A", "transfer_to": "B", "verified": False}]}];
    with patch.object(transit, "route", side_effect=providers.ProviderError("Synthetic route failure")) {
        assert transit.verify_transfer_paths(journeys, links, feed, 10);
    }
    assert "B" not in links["A"];
}
