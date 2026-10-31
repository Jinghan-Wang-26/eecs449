"""Dated scheduled-bus journeys. Calendar, routing and shopping rules stay in Jac."""
import math;
import from datetime { datetime, timedelta, timezone }
import from zoneinfo { ZoneInfo }
import from app_settings { instant }
import from integrations.providers { ProviderError }
import from integrations.transit { load_feed, walking_links, transfer_links, verify_transfer_paths, MAX_AGE }
import from planning.schedule { WEEKDAYS, minute, wall_time, weekly_hours }

glob BOARD_BUFFER: int = 120;
glob MAX_TRANSFERS: int = 2;

def active_services(feed: dict, day: any) -> set {
    key = day.strftime('%Y%m%d');
    if key < feed['start_date'] or key > feed['end_date'] { return set(); }
    weekday = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'][day.weekday()];
    services = {r['service_id'] for r in feed['calendar'] if r['start_date'] <= key <= r['end_date'] and r.get(weekday) == '1'};
    for row in feed['exceptions'] {
        if row['date'] == key {
            if row['exception_type'] == '1' { services.add(row['service_id']); }
            elif row['exception_type'] == '2' { services.discard(row['service_id']); }
        }
    }
    return services;
}

def service_epoch(day: any, zone: any) -> float {
    # GTFS counts elapsed seconds from local noon minus twelve hours, including
    # DST transition days. This is not always the civil midnight timestamp.
    return datetime(day.year, day.month, day.day, 12, tzinfo=zone).timestamp() - 43200;
}

def timed_trips(feed: dict, begin: float, finish: float) -> list {
    zone = ZoneInfo(feed['timezone']);
    first = datetime.fromtimestamp(begin, zone).date() - timedelta(days=1);
    last = datetime.fromtimestamp(finish, zone).date();
    trips = [];
    for offset in range((last - first).days + 1) {
        day = first + timedelta(days=offset); services = active_services(feed, day);
        base = service_epoch(day, zone);
        for trip in feed['trips'] {
            if trip['service_id'] not in services { continue; }
            stops = trip['stops'];
            if base + stops[-1]['arr'] < begin or base + stops[0]['dep'] > finish { continue; }
            value = dict(trip); value['base'] = base;
            value['service_date'] = day.isoformat();
            value['instance'] = day.isoformat() + ':' + trip['trip_id'];
            trips.append(value);
        }
    }
    return trips;
}

def service_stops(feed: dict, trips: list, begin: float, finish: float) -> dict {
    # Select by actual service instances before spending the bounded access-stop
    # budget. Nearby weekday-only stops must not hide a usable weekend stop.
    served = set();
    for trip in trips {
        for stop in trip['stops'] {
            if (stop['pickup'] and begin <= trip['base']+stop['dep'] <= finish) or (stop['dropoff'] and begin <= trip['base']+stop['arr'] <= finish) {
                served.add(stop['stop']);
            }
        }
    }
    return {key:feed['stops'][key] for key in served};
}

def walking_leg(start: str, end: str, begin: float, link: dict) -> dict {
    return {'kind':'WALK', 'from':start, 'to':end, 'start':begin, 'end':begin + link['seconds'],
        'source':link['source'], 'valid_until':link.get('valid_until', ''), 'verified':link.get('verified', True),
        'transfer_from':link.get('transfer_from',''), 'transfer_to':link.get('transfer_to','')};
}

def journey(feed: dict, trips: list, access: dict, egress: dict, links: dict, forbidden: set,
    begin: float, finish: float, max_transfers: int, origin_label: str, destination_label: str,
    arrival_allowed: any) -> any {
    stops = feed['stops']; previous = {}; results = [];
    for (key, link) in access.items() {
        previous[key] = {'origin': {'at':begin + link['seconds'], 'legs':[walking_leg(origin_label, stops[key]['name'], begin, link)],
            'walk_seconds':link['seconds'], 'last_trip':''}};
    }
    for round_no in range(min(max_transfers, MAX_TRANSFERS) + 1) {
        ready = {};
        for (stop, labels) in previous.items() {
            paths = {stop:{'seconds':0, 'min_seconds':0, 'source':'Same stop'}};
            if round_no > 0 {
                paths.update(links.get(stop, {}));
                paths = {k:v for (k,v) in paths.items() if (stop,k) not in forbidden};
            }
            for (to_stop, link) in paths.items() {
                for label in labels.values() {
                    legs = list(label['legs']);
                    if to_stop != stop { legs.append(walking_leg(stops[stop]['name'], stops[to_stop]['name'], label['at'], link)); }
                    ready.setdefault(to_stop, []).append({'at':label['at'] + link['seconds'],
                        'ready_at':label['at'] + max(link['seconds'] + BOARD_BUFFER, link.get('min_seconds', 0)),
                        'legs':legs, 'walk_seconds':label['walk_seconds'] + link['seconds'], 'last_trip':label['last_trip']});
                }
            }
        }
        following = {};
        for trip in trips {
            onboard = None; base = trip['base'];
            for stop_time in trip['stops'] {
                key = stop_time['stop']; arrival = base + stop_time['arr']; departure = base + stop_time['dep'];
                if arrival > finish { break; }
                if onboard is not None and stop_time['dropoff'] {
                    leg = {'kind':'BUS', 'from':stops[onboard['stop']]['name'], 'to':stops[key]['name'],
                        'from_stop_id':onboard['stop'], 'to_stop_id':key,
                        'from_stop_code':stops[onboard['stop']].get('code', onboard['stop']), 'to_stop_code':stops[key].get('code', key),
                        'start':onboard['dep'], 'end':arrival, 'route':trip['route_name'],
                        'headsign':trip.get('trip_headsign',''), 'trip_id':trip['trip_id'], 'service_date':trip['service_date'],
                        'source':'TheRide GTFS scheduled service'};
                    legs = onboard['legs'] + [leg];
                    label = {'at':arrival, 'legs':legs, 'walk_seconds':onboard['walk_seconds'], 'last_trip':trip['instance']};
                    existing = following.get(key, {}).get(trip['instance']);
                    if existing is None or arrival < existing['at'] { following.setdefault(key,{})[trip['instance']] = label; }
                    if key in egress {
                        final_at = arrival + egress[key]['seconds'];
                        if final_at <= finish and arrival_allowed(final_at) {
                            results.append({'arrival':final_at, 'legs':legs + [walking_leg(stops[key]['name'], destination_label, arrival, egress[key])],
                                'transfers':round_no, 'walk_seconds':label['walk_seconds'] + egress[key]['seconds']});
                        }
                    }
                }
                if not stop_time['pickup'] { continue; }
                for label in ready.get(key, []) {
                    if label['ready_at'] > departure or label['last_trip'] == trip['instance'] { continue; }
                    if onboard is None or label['walk_seconds'] < onboard['walk_seconds'] {
                        waiting = {'kind':'WAIT', 'from':stops[key]['name'], 'to':stops[key]['name'], 'start':label['at'], 'end':departure,
                            'source':'Scheduled connection, includes a two-minute boarding buffer'};
                        onboard = {'stop':key, 'dep':departure, 'legs':label['legs'] + [waiting], 'walk_seconds':label['walk_seconds']};
                    }
                }
            }
        }
        previous = following;
        if not previous { break; }
    }
    if not results { return None; }
    result = min(results, key=lambda r: dict: (r['arrival'], r['transfers'], r['walk_seconds']));
    legs = result['legs'];
    # Depart just in time for the chosen first bus rather than spend the entire
    # unused availability window waiting at the stop. Keep the boarding buffer.
    shift = max(0, legs[1]['end'] - legs[1]['start'] - BOARD_BUFFER);
    legs[0] = dict(legs[0]); legs[1] = dict(legs[1]);
    legs[0]['start'] += shift; legs[0]['end'] += shift; legs[1]['start'] += shift;
    result['departure'] = legs[0]['start'];
    result['wait_seconds'] = sum([l['end'] - l['start'] for l in legs if l['kind'] == 'WAIT']);
    result['max_walk_seconds'] = max([l['end'] - l['start'] for l in legs if l['kind'] == 'WALK']);
    return result;
}

def store_allows(arrival: float, hours: any, zone: any) -> bool {
    if hours is None { return True; }
    local = datetime.fromtimestamp(arrival, zone);
    for (a,b) in hours[local.weekday()] {
        start = wall_time(local.date(), a, zone); end = wall_time(local.date(), b, zone);
        if start is not None and end is not None and start.timestamp() <= arrival and arrival + 1200 <= end.timestamp() { return True; }
    }
    return False;
}

def availability(windows: list, now: str, zone_name: str) -> list {
    zone = ZoneInfo(zone_name); current = instant(now).astimezone(zone);
    earliest = math.ceil(current.timestamp() / 60) * 60 + 300;
    values = [];
    for offset in range(8) {
        day = current.date() + timedelta(days=offset);
        for window in windows {
            (weekday, interval) = window.split();
            if weekday != WEEKDAYS[day.weekday()] { continue; }
            (a,b) = interval.split('-'); begin = wall_time(day,minute(a),zone); end = wall_time(day,minute(b),zone);
            if begin is None or end is None { continue; }
            start = max(begin.timestamp(), earliest);
            if start + 1200 < end.timestamp() { values.append((start,end.timestamp())); }
        }
    }
    return sorted(set(values));
}

def present_journey(value: dict, zone: any) -> dict {
    result = dict(value); legs = [];
    for original in value['legs'] {
        leg = dict(original);
        leg['departure_at'] = datetime.fromtimestamp(leg['start'],zone).isoformat(timespec='seconds');
        leg['arrival_at'] = datetime.fromtimestamp(leg['end'],zone).isoformat(timespec='seconds');
        leg['minutes'] = round((leg['end'] - leg['start']) / 60, 1);
        legs.append(leg);
    }
    result['legs'] = legs;
    result['minutes'] = math.ceil((value['arrival'] - value['departure']) / 60);
    result['departure_at'] = datetime.fromtimestamp(value['departure'],zone).isoformat(timespec='seconds');
    result['arrival_at'] = datetime.fromtimestamp(value['arrival'],zone).isoformat(timespec='seconds');
    return result;
}

def bus_visit(origin: dict, store: dict, profile: dict, now: str) -> dict {
    feed = load_feed(); zone_name = origin.get('timezone') or feed['timezone']; zone = ZoneInfo(zone_name);
    store_zone_name = store.get('timezone') or feed['timezone']; store_zone = ZoneInfo(store_zone_name);
    slots = availability(profile['free_windows'], now, zone_name);
    if not slots { raise ProviderError('No upcoming free-time window leaves room for a bus trip and 20 minutes shopping.'); }
    feed_zone = ZoneInfo(feed['timezone']);
    covered = [(a,b) for (a,b) in slots if feed['start_date'] <= datetime.fromtimestamp(a,feed_zone).strftime('%Y%m%d') <= feed['end_date']];
    if not covered { raise ProviderError('TheRide timetable does not cover your upcoming shopping dates. Refresh later; expired schedules are not used.'); }
    maximum = profile['max_walk_min'];
    walk_cache = {}; diagnostics = []; service_windows = 0; outbound_found = False;
    transfers = min(profile.get('max_transfers',1), MAX_TRANSFERS);
    (links,forbidden) = transfer_links(feed,maximum) if transfers > 0 else ({},set());
    hours = weekly_hours(store.get('opening_hours',''));
    refinements = 0;
    for (begin,finish) in covered {
        trips = timed_trips(feed,begin,finish); served = service_stops(feed,trips,begin,finish);
        if not served { continue; }
        service_windows += 1; cache_key = tuple(sorted(served));
        try {
            if cache_key not in walk_cache {
                walk_cache[cache_key] = [walking_links([point['lat'],point['lon']],served,maximum) for point in [origin,store]];
            }
            ((home_out,home_in),(store_out,store_in)) = walk_cache[cache_key];
        } except ProviderError as error { diagnostics.append(str(error)); continue; }
        outbound = None; returning = None;
        verified = False;
        for attempt in range(12) {
            outbound = journey(feed,trips,home_out,store_in,links,forbidden,begin,finish - 1200,transfers,
                origin.get('address','Confirmed starting address'),store['name'],lambda arrival: float: store_allows(arrival,hours,store_zone));
            if outbound is None { break; }
            outbound_found = True;
            checkout = outbound['arrival'] + 1200;
            returning = journey(feed,trips,store_out,home_in,links,forbidden,checkout,finish,transfers,
                store['name'],origin.get('address','Confirmed starting address'),lambda arrival: float: True);
            if returning is None { break; }
            if not verify_transfer_paths([outbound,returning],links,feed,maximum) { verified = True; break; }
            refinements += 1;
            if refinements >= 12 { raise ProviderError('Transit transfer verification reached its bounded search limit. Try a lower transfer limit, another store or a wider time window. No unverified walking connections were accepted.'); }
        }
        if not verified { continue; }
        checkout = outbound['arrival'] + 1200;
        out = present_journey(outbound,zone); back = present_journey(returning,zone);
        validity = [instant(feed['fetched_at']).timestamp() + MAX_AGE, instant(now).timestamp() + 900];
        for leg in out['legs'] + back['legs'] {
            if leg.get('valid_until') { validity.append(instant(leg['valid_until']).timestamp()); }
        }
        end_valid = min(validity);
        if end_valid <= instant(now).timestamp() { raise ProviderError('A transit walking connection expired. Refresh recommendations.'); }
        duration = math.ceil((returning['arrival'] - outbound['departure']) / 60);
        wait_at_store = math.ceil((returning['departure'] - checkout) / 60);
        return {'mode':'BUS', 'min':duration - 20, 'total_min':duration, 'shopping_min':20,
            'outbound_min':out['minutes'], 'return_min':back['minutes'], 'store_wait_min':wait_at_store,
            'walk_min':math.ceil(max(outbound['max_walk_seconds'],returning['max_walk_seconds']) / 60),
            'total_walk_min':math.ceil((outbound['walk_seconds'] + returning['walk_seconds']) / 60),
            'wait_min':math.ceil((outbound['wait_seconds'] + returning['wait_seconds']) / 60) + wait_at_store,
            'transfers':max(outbound['transfers'],returning['transfers']), 'cost':None,
            'source':'theride_gtfs', 'scheduled_only':True, 'outbound':out, 'returning':back,
            'observed_at':feed['fetched_at'], 'valid_until':datetime.fromtimestamp(end_valid,zone).isoformat(timespec='seconds'),
            'departure_at':out['departure_at'], 'arrival_at':datetime.fromtimestamp(outbound['arrival'],store_zone).isoformat(timespec='seconds'),
            'shopping_end_at':datetime.fromtimestamp(checkout,store_zone).isoformat(timespec='seconds'),
            'leave_store_at':datetime.fromtimestamp(checkout,store_zone).isoformat(timespec='seconds'),
            'return_at':back['arrival_at'], 'timezone':zone_name, 'store_timezone':store_zone_name,
            'window':datetime.fromtimestamp(outbound['departure'],zone).strftime('%Y-%m-%d %a %H:%M') + '–' + datetime.fromtimestamp(returning['arrival'],zone).strftime('%H:%M') + ' ' + zone_name,
            'hours_status':'REGULAR_HOURS_FIT' if hours is not None else 'UNKNOWN', 'timezone_notice':'', 'blocker':'', 'violations':[],
            'feed':{'version':feed['version'], 'sha256':feed['fingerprint'], 'start_date':feed['start_date'], 'end_date':feed['end_date'], 'fetched_at':feed['fetched_at'], 'source_url':feed['source_url']},
            'notice':'Scheduled TheRide service only; live delays, cancellations and detours are unavailable. Intermediate stop times may be estimated by the agency. Fares are unknown. Search checks up to eight access stops with scheduled service in the selected window within 1.2 km and at most two transfers per direction; nearby platform transfers are bounded to four neighbours within 150 m, plus explicit GTFS connections. Every displayed transfer walk is map-verified.'};
    }
    reason = 'No outbound connection reaches this store within your walking/transfer limits and recorded store hours.';
    if service_windows == 0 { reason = 'No scheduled service overlaps the checked free-time windows.'; }
    elif outbound_found { reason = 'An outbound bus was found, but no verified return fits before your free time ends after 20 minutes shopping.'; }
    elif diagnostics { reason = ' '.join(list(dict.fromkeys(diagnostics))); }
    checked = ', '.join([datetime.fromtimestamp(a,zone).strftime('%Y-%m-%d %H:%M')+'–'+datetime.fromtimestamp(b,zone).strftime('%H:%M') for (a,b) in covered]);
    raise ProviderError('No scheduled TheRide round trip found. '+reason+' Checked '+checked+' '+zone_name+'. This bounded search is not proof that no bus exists; check the timetable or try another time/store.');
}
