"""Rebase fictional observations only; raw fixtures remain reproducible."""
from datetime import timedelta
from app_settings import instant


def rebase_fixture(data, now=""):
    if not now:
        return data  # Explicit low-level fixture mode for historical regression tests.
    anchor = instant(now).replace(hour=0, minute=0, second=0, microsecond=0)
    original = instant(data["observed_at"])
    for offer in data["offers"]:
        observed = instant(offer.get("observed_at", data["observed_at"]))
        expires = instant(offer.get("valid_until", data["valid_until"]))
        if expires <= observed or observed > original:
            raise ValueError("Invalid mock observation interval")
        # Preserve age and TTL; an intentionally stale fixture stays stale.
        shifted = anchor + (observed - original)
        offer["observed_at"] = shifted.isoformat(timespec="seconds")
        offer["valid_until"] = (shifted + (expires - observed)).isoformat(timespec="seconds")
    return data
