"""Validate user/LLM input before any graph mutation."""
import math;
import re;
import from datetime { datetime }
glob MODES: set = {"WALK", "BUS", "CAR", "BIKE", "RIDESHARE"};
glob PROFILE_FIELDS: set = {"transport", "carry_limit_kg", "weekly_budget", "max_walk_min", "max_transfers", "time_value_per_hour", "free_windows", "dietary", "memberships", "brand_prefs", "locked", "transport_cost", "tax_rate"};

def number(value: any, low: float, high: float, field: str) -> float {
    if isinstance(value, bool) {
        raise ValueError(f'{field} must be a number.');
    }
    try {
        value = float(value);
    } except (ValueError, TypeError) {
        raise ValueError(f'{field} must be a number.');
    }
    if (not math.isfinite(value) or not (low <= value <= high)) {
        raise ValueError(f'{field} must be between {low} and {high}.');
    }
    return value;
}
def strings(value: any, field: str, max_count: int = 20) -> list {
    if (
        not isinstance(value, `list)
        or (len(value) > max_count)
        or `any(
            (not isinstance(x, str) or not x.strip() or (len(x) > 100)) for x in value
        )
    ) {
        raise ValueError(f'{field} must be a short list of nonempty strings.');
    }
    return `list(`dict.fromkeys(x.strip() for x in value));
}
def profile_patch(data: any) -> dict {
    if (not isinstance(data, `dict) or (`set(data) - PROFILE_FIELDS)) {
        raise ValueError('Unsupported profile fields.');
    }
    out = {};
    bounds = {
        'carry_limit_kg': (0.1, 100),
        'weekly_budget': (0, 10000),
        'max_walk_min': (0, 240),
        'max_transfers': (0, 10),
        'time_value_per_hour': (0, 1000),
        'transport_cost': (0, 1000),
        'tax_rate': (0, 0.3)
    };
    for (name, value) in data.items() {
        if (name in bounds) {
            value = number(value, bounds[name][0], bounds[name][1], name);
            out[name] = int(value)
                if (name in ('max_walk_min', 'max_transfers'))
                else value;
        } elif (name == 'transport') {
            value = strings(value, name, 5);
            if (not value or (`set(value) - MODES)) {
                raise ValueError('Choose at least one supported transport mode.');
            }
            out[name] = value;
        } elif (name == 'free_windows') {
            value = strings(value, name);
            for window in value {
                `match = re.fullmatch(
                    r'(MON|TUE|WED|THU|FRI|SAT|SUN) (\d{2}:\d{2})-(\d{2}:\d{2})', window
                );
                if not `match {
                    raise ValueError('Use windows such as SAT 14:00-17:00.');
                }
                (start, end) = (`match[2], `match[3]);
                try {
                    datetime.strptime(start, '%H:%M');
                    datetime.strptime(end, '%H:%M');
                } except ValueError {
                    raise ValueError('Invalid time window.');
                }
                if (start >= end) {
                    raise ValueError(
                        'Time window end must follow start on the same day.'
                    );
                }
            }
            out[name] = value;
        } elif (name in ('dietary', 'memberships', 'locked')) {
            out[name] = strings(value, name);
            if ((name == 'locked') and (`set(out[name]) - PROFILE_FIELDS)) {
                raise ValueError('Unknown locked profile field.');
            }
        } elif (name == 'brand_prefs') {
            if (
                not isinstance(value, `dict)
                or (len(value) > 20)
                or `any(
                    (
                        not isinstance(k, str)
                        or not isinstance(v, str)
                        or ((len(k) + len(v)) > 200)
                    ) for (k, v) in value.items()
                )
            ) {
                raise ValueError('Invalid brand preferences.');
            }
            out[name] = value;
        }
    }
    return out;
}
def need_spec(data: any) -> dict {
    if not isinstance(data, `dict) {
        raise ValueError('A shopping need must be an object.');
    }
    category = data.get('category', data.get('type', ''));
    if not isinstance(category, str) {
        raise ValueError('Product category must be text.');
    }
    category = category.strip().lower();
    if not (2 <= len(category) <= 80) {
        raise ValueError('Enter a product category or search term (2–80 characters).');
    }
    qty = number(data.get('qty', 1), 1, 20, 'quantity');
    if (qty != int(qty)) {
        raise ValueError('Quantity must be a whole number of packages.');
    }
    return {
        'type': category,
        'qty': int(qty),
        'brand': str(data.get('brand', ''))[:100],
        'size': str(data.get('size', ''))[:100],
        'substitutes': 'ask'
    };
}
