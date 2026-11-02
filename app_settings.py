"""Validated application settings and timezone-aware clocks (stdlib only)."""

from datetime import datetime, timedelta, timezone
from pathlib import Path
import math
import os
import tomllib
from zoneinfo import ZoneInfo

DEFAULTS = {
    "data_mode": "mock", "timezone": "America/New_York",
    "max_fulfillment_channels": 2, "max_plan_options": 3,
    "max_discovery_items_per_week": 3, "reminder_cooldown_hours": 24,
    "quiet_hours_start": 22, "quiet_hours_end": 8,
    "allow_substitutions": "ask", "auto_purchase": False,
    "material_price_change": 0.5, "background_check_minutes": 30,
}


def get_settings(overrides: dict | None = None) -> dict:
    config = dict(DEFAULTS)
    # CARTCOMPASS_SETTINGS points an isolated run (scripts/verify_e2e.py) at its own file.
    path = Path(os.environ.get("CARTCOMPASS_SETTINGS") or Path(__file__).with_name("app.toml"))
    if path.exists():
        config.update(tomllib.loads(path.read_text()))
    config.update(overrides or {})
    unknown = set(config) - set(DEFAULTS)
    if unknown:
        raise ValueError(f"Unknown application settings: {sorted(unknown)}")
    if config["data_mode"] not in ("mock", "live"):
        raise ValueError("data_mode must be mock or live")
    ZoneInfo(config["timezone"])
    bounds = {
        "max_fulfillment_channels": (1, 2), "max_plan_options": (1, 3),
        "max_discovery_items_per_week": (0, 20), "reminder_cooldown_hours": (0, 720),
        "quiet_hours_start": (0, 23), "quiet_hours_end": (0, 23),
        "background_check_minutes": (5, 1440),
    }
    for name, (low, high) in bounds.items():
        value = config[name]
        if type(value) is not int or not low <= value <= high:
            raise ValueError(f"{name} must be an integer from {low} to {high}")
    value = config["material_price_change"]
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError("material_price_change must be a finite nonnegative number")
    if config["allow_substitutions"] != "ask" or config["auto_purchase"] is not False:
        raise ValueError("Substitutions require confirmation; automatic purchases are unsupported")
    return config


def instant(value: str, settings: dict | None = None) -> datetime:
    zone = ZoneInfo((settings or get_settings())["timezone"])
    dt = datetime.fromisoformat(value) if value else datetime.now(zone)
    local = dt.replace(tzinfo=zone) if dt.tzinfo is None else dt.astimezone(zone)
    # A fixed offset keeps the local wall clock but compares and subtracts by real time.
    # Datetimes sharing one ZoneInfo compare by wall clock, wrong in the repeated DST hour.
    return local.astimezone(timezone(local.utcoffset()))


def stamp(value: str = "", settings: dict | None = None) -> str:
    return instant(value, settings).isoformat(timespec="seconds")


def elapsed_hours(before: str, after: str, settings: dict | None = None) -> float:
    return (instant(after, settings).astimezone(timezone.utc) -
            instant(before, settings).astimezone(timezone.utc)).total_seconds() / 3600


def due(value: str, now: str, settings: dict | None = None) -> bool:
    return bool(value) and instant(value, settings) <= instant(now, settings)


def later(value: str, hours: float, settings: dict | None = None) -> str:
    return stamp((instant(value, settings) + timedelta(hours=hours)).isoformat(), settings)


def week_key(now: str, settings: dict | None = None) -> str:
    year, week, _ = instant(now, settings).isocalendar()
    return f"{year}-W{week:02d}"


def quiet(now: str, settings: dict | None = None) -> bool:
    cfg = settings or get_settings()
    hour = instant(now, cfg).hour
    start, end = cfg["quiet_hours_start"], cfg["quiet_hours_end"]
    return (start <= hour < end if start < end else hour >= start or hour < end) if start != end else False
