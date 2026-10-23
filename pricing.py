"""Package-price comparison in USD. US customary units; never infer density."""
import math
import re

# Canonical unit, amount per package unit. Counts refer to pieces, not weight.
UNITS = {
    "kg": ("kg", 1), "g": ("kg", .001), "lb": ("kg", .45359237),
    "lbs": ("kg", .45359237), "oz": ("kg", .028349523125),
    "l": ("L", 1), "ml": ("L", .001), "gal": ("L", 3.785411784),
    "fl oz": ("L", .0295735295625), "ct": ("piece", 1),
    "count": ("piece", 1), "piece": ("piece", 1),
}


def package_size(size=0, unit="", label=""):
    if type(size) in (int, float) and math.isfinite(size) and size > 0:
        normalized = " ".join(str(unit).lower().split())
        return (size, normalized) if normalized in UNITS else (None, "")
    # Exact simple labels only: no guessing about multipacks or mixed dimensions.
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(kg|g|lbs?|oz|l|ml|gal|fl\s+oz|ct|count|piece)\s*", label or "", re.I)
    if match:
        return package_size(float(match[1]), match[2])
    return None, ""


def price_details(price, size=0, unit="", label=""):
    result = {"package_price": None, "unit_price": None, "unit": "",
              "price_label": "Package price unknown", "unit_price_label": "Unit price unavailable: package size unknown"}
    if type(price) not in (int, float) or not math.isfinite(price) or price < 0:
        result["unit_price_label"] = "Unit price unavailable: package price unknown"
        return result
    result.update(package_price=price, price_label=f"${price:.2f} / package")
    amount, source_unit = package_size(size, unit, label)
    if amount is None:
        return result
    canonical, factor = UNITS[source_unit]
    value = price / (amount * factor)
    if not math.isfinite(value):
        return result
    result.update(unit_price=round(value, 4), unit=canonical,
                  unit_price_label=f"${value:.2f} / {canonical}")
    return result
