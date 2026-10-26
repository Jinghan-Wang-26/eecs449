"""Dated visit scheduling. Unknown/complex opening hours never imply open."""
import re;
import from datetime { datetime, timedelta, timezone }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }
import from app_settings { get_settings, instant }

glob DAYS: list = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
glob WEEKDAYS: list = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

def conversation_clock(origin: dict) -> dict {
    name = origin.get('timezone') or get_settings()['timezone'];
    try { zone = ZoneInfo(name); }
    except (ValueError, ZoneInfoNotFoundError) { name = get_settings()['timezone']; zone = ZoneInfo(name); }
    return {'local_time': datetime.now(zone).isoformat(timespec='seconds'), 'timezone': name};
}

def minute(value: str) -> int {
    if value == '24:00' { return 1440; }
    datetime.strptime(value, '%H:%M');
    return int(value[:2]) * 60 + int(value[3:]);
}

def weekly_hours(raw: any) -> any {
    # Support only unambiguous weekly rules. Holidays, overnight ranges, seasonal
    # exceptions and comments must remain unknown instead of being discarded.
    if not isinstance(raw, str) or not raw.strip() { return None; }
    raw = raw.strip();
    if raw == '24/7' { return {i: [(0, 1440)] for i in range(7)}; }
    if raw in ['off', 'closed'] { return {i: [] for i in range(7)}; }
    result = {i: [] for i in range(7)}; seen = [];
    for rule in raw.split(';') {
        rule = rule.strip();
        m = re.fullmatch(r'(?:(Mo|Tu|We|Th|Fr|Sa|Su)([-,A-Za-z]*) )?((?:\d{2}:\d{2}-\d{2}:\d{2})(?:,\d{2}:\d{2}-\d{2}:\d{2})*|off|closed)', rule);
        if m is None { return None; }
        selected = [];
        selector = (m[1] or '') + (m[2] or '');
        if not selector { selected = `list(range(7)); }
        else {
            for part in selector.split(',') {
                pair = part.split('-');
                if len(pair) > 2 or `any([v not in DAYS for v in pair]) { return None; }
                start = DAYS.index(pair[0]); end = DAYS.index(pair[-1]);
                selected.extend([(start + i) % 7 for i in range((end - start) % 7 + 1)]);
            }
        }
        if `any([i in seen for i in selected]) { return None; }
        spans = [];
        if m[3] not in ['off', 'closed'] {
            for span in m[3].split(',') {
                try {
                    (a, b) = span.split('-'); start = minute(a); end = minute(b);
                } except ValueError { return None; }
                if start >= end { return None; }
                spans.append((start, end));
            }
        }
        for i in selected { result[i] = spans; }
        seen.extend(selected);
    }
    return result;
}

def wall_time(day: any, minutes: int, zone: any) -> any {
    value = datetime(day.year, day.month, day.day, tzinfo=zone) + timedelta(minutes=minutes);
    # Ambiguous/nonexistent local times on DST changes are not silently guessed.
    if value.utcoffset() != value.replace(fold=1).utcoffset() { return None; }
    if value.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) != value.replace(tzinfo=None) { return None; }
    return value;
}

def schedule_visit(windows: list, travel: dict, store: dict, now: str, origin_zone: str = '') -> dict {
    zone_name = origin_zone or get_settings()['timezone'];
    zone_notice = '';
    try { zone = ZoneInfo(zone_name); }
    except (ValueError, ZoneInfoNotFoundError) {
        zone_name = get_settings()['timezone']; zone = ZoneInfo(zone_name);
        zone_notice = 'Address timezone unavailable; using configured timezone. Confirm it before travelling.';
    }
    if not origin_zone { zone_notice = 'Address timezone unavailable; using configured timezone. Confirm it before travelling.'; }
    store_zone_name = store.get('timezone') or zone_name;
    try { store_zone = ZoneInfo(store_zone_name); }
    except (ValueError, ZoneInfoNotFoundError) { store_zone = zone; store_zone_name = zone_name; }
    current = instant(now).astimezone(zone).astimezone(timezone.utc);
    # Leave a short review/preparation buffer after provider requests finish.
    earliest = current.replace(second=0, microsecond=0) + timedelta(minutes=5);
    local_day = current.astimezone(zone).date();
    duration = int(travel['min']) + 20;
    outbound = travel.get('outbound_min'); returning = travel.get('return_min');
    legs_known = isinstance(outbound, (int, float)) and isinstance(returning, (int, float));
    raw = store.get('opening_hours', ''); hours = weekly_hours(raw);
    if not legs_known { hours = None; }
    options = []; time_fit = False;
    for offset in range(8) {
        day = local_day + timedelta(days=offset);
        for window in windows {
            (weekday, interval) = window.split();
            if weekday != WEEKDAYS[day.weekday()] { continue; }
            (a, b) = interval.split('-');
            begin = wall_time(day, minute(a), zone); finish = wall_time(day, minute(b), zone);
            if begin is None or finish is None { continue; }
            begin = max(begin.astimezone(timezone.utc), earliest); finish = finish.astimezone(timezone.utc);
            if begin + timedelta(minutes=duration) > finish { continue; }
            time_fit = True;
            starts = [begin];
            if hours is not None {
                starts = [];
                # A user's availability can straddle midnight in the store timezone.
                first_day = begin.astimezone(store_zone).date();
                for shift in range(2) {
                    store_day = first_day + timedelta(days=shift);
                    for (opening, closing) in hours[store_day.weekday()] {
                        opened = wall_time(store_day, opening, store_zone); closed = wall_time(store_day, closing, store_zone);
                        if opened is None or closed is None { continue; }
                        opened = opened.astimezone(timezone.utc); closed = closed.astimezone(timezone.utc);
                        departure = max(begin, opened - timedelta(minutes=outbound));
                        shopping_end = departure + timedelta(minutes=outbound + 20);
                        if shopping_end <= closed and departure + timedelta(minutes=duration) <= finish { starts.append(departure); }
                    }
                }
            }
            for start in starts {
                stop = start + timedelta(minutes=duration);
                depart = start.astimezone(zone); returned = stop.astimezone(zone);
                arrival = (start + timedelta(minutes=outbound)).astimezone(store_zone) if legs_known else None;
                leave = (start + timedelta(minutes=outbound + 20)).astimezone(store_zone) if legs_known else None;
                options.append({'departure_at': depart.isoformat(timespec='minutes'),
                    'arrival_at': arrival.isoformat(timespec='minutes') if arrival else '',
                    'leave_store_at': leave.isoformat(timespec='minutes') if leave else '',
                    'return_at': returned.isoformat(timespec='minutes'), 'timezone': zone_name,
                    'store_timezone': store_zone_name,
                    'window': depart.strftime('%Y-%m-%d %a %H:%M') + '–' + returned.strftime('%H:%M') + ' ' + zone_name,
                    'hours_status': 'REGULAR_HOURS_FIT' if hours is not None else 'UNKNOWN',
                    'timezone_notice': zone_notice, 'blocker': ''});
            }
        }
    }
    if options { return min(options, key=lambda x: dict: x['departure_at']); }
    return {'departure_at': '', 'arrival_at': '', 'leave_store_at': '', 'return_at': '', 'window': '',
        'timezone': zone_name, 'store_timezone': store_zone_name, 'timezone_notice': zone_notice,
        'hours_status': 'NO_OPEN_SLOT' if hours is not None and time_fit else 'UNKNOWN',
        'blocker': 'No upcoming free-time window overlaps the recorded regular opening hours.' if hours is not None and time_fit else 'No upcoming free-time window fits travel plus 20 minutes shopping.'};
}
