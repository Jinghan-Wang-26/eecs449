"""UserProfile: long-term settings, plus the current trip's constraints kept separately."""

enum Transport { WALK, BUS, CAR, BIKE, RIDESHARE }

node UserProfile {
    has home_area: str = "",
        home_address: str = "",            # asked for only when exact delivery coverage matters
        transport: list[str] = ["WALK"],   # Transport names
        max_walk_min: int = 15,
        max_transfers: int = 1,
        carry_limit_kg: float = 6.0,
        weekly_budget: float = 0.0,
        free_windows: list[str] = [],      # e.g. "SAT 14:00-17:00"
        brand_prefs: dict = {},            # category -> preferred brand
        dietary: list[str] = [],
        memberships: list[str] = [],
        weights: dict = {"cost": 0.4, "time": 0.3, "effort": 0.2, "risk": 0.1},
        locked: list[str] = [];            # fields learned preferences may not overwrite

    """Learned updates go through here, so they never override a field the user locked."""
    def learn(field: str, value: any) -> bool {
        if field in self.locked {
            return False;
        }
        setattr(self, field, value);
        return True;
    }
}

"""This trip only, e.g. no bus this week. Deleted when the trip ends."""
node TripConstraints {
    has budget: float = -1.0,              # -1 = use the profile value
        transport: list[str] = [],         # empty = use the profile value
        deadline: str = "",
        free_windows: list[str] = [],
        notes: str = "";
}

"""Profile merged with trip overrides; planning reads only this."""
def effective_constraints(p: UserProfile, t: TripConstraints | None) -> dict {
    c = {
        "transport": p.transport,
        "max_walk_min": p.max_walk_min,
        "max_transfers": p.max_transfers,
        "carry_limit_kg": p.carry_limit_kg,
        "budget": p.weekly_budget,
        "free_windows": p.free_windows,
        "deadline": "",
        "weights": p.weights
    };
    if t is not None {
        if t.budget >= 0 {
            c["budget"] = t.budget;
        }
        if t.transport {
            c["transport"] = t.transport;
        }
        if t.free_windows {
            c["free_windows"] = t.free_windows;
        }
        c["deadline"] = t.deadline;
    }
    return c;
}
