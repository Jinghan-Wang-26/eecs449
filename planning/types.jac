"""Planning inputs and results. Providers turn Store/Offer data into Channel and Quote;
planning never reads raw sources. Times are weekday windows like "SAT 14:00-17:00"."""

glob DAYS: list = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];

obj Need {
    has key: str,                          # product type, matches Quote.need
        qty: int = 1,
        priority: int = 2;
}

"""One way to get items from one store: an in-store trip, a pickup, or a delivery order."""
obj Channel {
    has id: str,
        store: str,                        # display name
        store_key: str = "",               # Store.key in the catalog
        kind: str = "IN_STORE",            # IN_STORE / PICKUP / DELIVERY
        mode: str = "",                    # transport the route assumes: WALK / BUS / CAR ...
        travel_min: int = 0,               # round trip
        shop_min: int = 0,
        walk_min: int = 0,
        transfers: int = 0,
        transport_cost: float = 0.0,
        windows: list[str] = [],           # store hours, or delivery windows
        ready_day: str = "",               # DELIVERY: earliest arrival day
        covers_area: bool = True,
        delivery_fee: float = 0.0,
        fee_known: bool = True,
        fee_max: float = 0.0,              # upper estimate when the fee is not verified
        service_fee_pct: float = 0.0,
        free_over: float = 0.0,            # 0 = no free-delivery threshold
        min_order: float = 0.0,
        tip: float = 0.0,
        tax_rate: float = 0.06;
}

"""One priced, timestamped offer for one need through one channel."""
obj Quote {
    has need: str,
        channel: str,
        price: float,                      # per unit, before discounts
        weight_kg: float = 0.0,            # per unit
        discount: float = 0.0,             # per unit
        member_only: str = "",             # the discount requires this membership
        stock: str = "YES",                # YES / NO / UNKNOWN
        observed_at: str = "",
        offer: any = None;                 # the catalog Offer this came from
}

obj CostBreakdown {
    has merchandise: float = 0.0,
        discounts: float = 0.0,
        tax: float = 0.0,
        delivery_fees: float = 0.0,
        service_fees: float = 0.0,
        tips: float = 0.0,
        transport: float = 0.0,
        unverified_max: float = 0.0,       # extra that may apply where fees are not verified
        subtotals: dict = {},              # channel id -> merchandise after discounts
        per_channel: dict = {},            # channel id -> {"tax", "delivery", "service", "tip", "transport"}
        notes: list[str] = [];

    def total() -> float {
        return round(
            self.merchandise - self.discounts + self.tax + self.delivery_fees
            + self.service_fees + self.tips + self.transport,
            2
        );
    }

    def total_max() -> float {
        return round(self.total() + self.unverified_max, 2);
    }

    def as_dict() -> dict {
        return {
            "merchandise": round(self.merchandise, 2),
            "discounts": round(self.discounts, 2),
            "tax": round(self.tax, 2),
            "delivery_fees": round(self.delivery_fees, 2),
            "service_fees": round(self.service_fees, 2),
            "tips": round(self.tips, 2),
            "transport": round(self.transport, 2),
            "total": self.total(),
            "total_max": self.total_max()
        };
    }
}

obj Candidate {
    has assignment: dict = {},             # need key -> Quote
        channels: list[str] = [],          # channel ids used
        unmet: list[str] = [],
        cost: CostBreakdown = CostBreakdown(),
        active_min: int = 0,
        time_cost: float = 0.0,            # active_min priced at the user's time value
        carried_kg: float = 0.0,
        transfers: int = 0,
        unknowns: int = 0,
        ready_day: str = "",
        days: dict = {},                   # channel id -> day of the trip or delivery
        violations: list[str] = [],
        warnings: list[str] = [],
        score: float = 0.0,
        labels: list[str] = [],
        skipped: str = "";                 # why a cheaper plan was not recommended instead

    def feasible() -> bool {
        return len(self.violations) == 0 and len(self.unmet) == 0;
    }

    """Money paid plus time spent, in dollars. Used for ranking, never shown as a price."""
    def effective_cost() -> float {
        return round(self.cost.total() + self.time_cost, 2);
    }
}

def day_index(day: str) -> int {
    return DAYS.index(day);
}

def to_min(hhmm: str) -> int {
    parts = hhmm.split(":");
    return int(parts[0]) * 60 + int(parts[1]);
}

"""("SAT", 840, 1020) from "SAT 14:00-17:00"."""
def parse_window(w: str) -> tuple {
    parts = w.split(" ");
    span = parts[1].split("-");
    return (parts[0], to_min(span[0]), to_min(span[1]));
}

"""Earliest day, not before min_day, where a user window and a channel window
overlap by at least need_min minutes. "" if there is none."""
def first_fit(user_windows: list, channel_windows: list, need_min: int, min_day: str = "") -> str {
    best = -1;
    floor = day_index(min_day) if min_day else 0;
    for uw in user_windows {
        u = parse_window(uw);
        for cw in channel_windows {
            c = parse_window(cw);
            if u[0] != c[0] or day_index(u[0]) < floor {
                continue;
            }
            overlap = min(u[2], c[2]) - max(u[1], c[1]);
            if overlap >= need_min and (best < 0 or day_index(u[0]) < best) {
                best = day_index(u[0]);
            }
        }
    }
    return DAYS[best] if best >= 0 else "";
}
