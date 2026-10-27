"""Sequential two-store road or scheduled-bus itineraries, with a verified return."""
import math;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from app_settings { instant, get_settings }
import from integrations.providers { ProviderError }
import from integrations.transit { load_feed, walking_links, transfer_links, verify_transfer_paths, MAX_AGE }
import from planning.transit { availability, timed_trips, journey, present_journey, store_allows, service_stops }
import from planning.schedule { weekly_hours, wall_time }

def trip_slots(context: dict, now: str, delivery: any = None) -> list {
    zone = context['origin'].get('timezone') or get_settings()['timezone'];
    start = (instant(now)+timedelta(minutes=10)).isoformat() if delivery is not None else now;
    slots = availability(context['profile']['free_windows'],start,zone);
    if delivery is None { return slots; }
    start = instant(delivery['window_start']).timestamp(); end = instant(delivery['window_end']).timestamp();
    out = [];
    for (a,b) in slots {
        if a < start { out.append((a,min(b,start))); }
        if b > end { out.append((max(a,end),b)); }
    }
    return [(a,b) for (a,b) in out if b-a > 1200];
}

def shop_start(arrival: float, store: dict, zone: any) -> any {
    hours = weekly_hours(store.get('opening_hours',''));
    if hours is None { return arrival; }
    local = datetime.fromtimestamp(arrival,zone);
    for (a,b) in sorted(hours[local.weekday()]) {
        opening = wall_time(local.date(),a,zone); closing = wall_time(local.date(),b,zone);
        if opening is None or closing is None { continue; }
        begin = max(arrival,opening.timestamp());
        if begin + 1200 <= closing.timestamp() { return begin; }
    }
    return None;
}

def route_result(stores: list, segments: list, stops: list, mode: str, context: dict, now: str, valid_until: str, feed: any = None) -> dict {
    zone_name = context['origin'].get('timezone') or get_settings()['timezone']; zone = ZoneInfo(zone_name);
    depart = segments[0]['departure_at']; returned = segments[-1]['arrival_at'];
    duration = math.ceil((instant(returned)-instant(depart)).total_seconds()/60);
    all_legs = [leg for segment in segments for leg in segment.get('legs', [])];
    waits = sum([s.get('wait_min',0) for s in stops]);
    travel_walk = max([leg['minutes'] for leg in all_legs if leg['kind']=='WALK'] or [0]);
    walk_total = sum([leg['minutes'] for leg in all_legs if leg['kind']=='WALK']);
    route = {'mode':mode, 'segments':segments, 'stops':stops, 'min':duration-20*len(stores), 'total_min':duration,
        'shopping_min':20*len(stores), 'departure_at':depart,'return_at':returned,'arrival_at':stops[0]['arrival_at'],
        'leave_store_at':stops[-1]['leave_at'],'timezone':zone_name,'store_timezone':zone_name,
        'window':depart+' → '+returned,'violations':[],'blocker':'','timezone_notice':'',
        'hours_status':'REGULAR_HOURS_FIT' if all([s['hours_known'] for s in stops]) else 'UNKNOWN',
        'source':'theride_gtfs' if mode=='BUS' else 'geoapify','scheduled_only':mode=='BUS',
        'observed_at':now,'valid_until':valid_until,'cost':0 if mode in ['WALK','BIKE'] else None,
        'walk_min':math.ceil(travel_walk),'total_walk_min':math.ceil(walk_total),'store_wait_min':waits,
        'wait_min':math.ceil(sum([leg['minutes'] for leg in all_legs if leg['kind']=='WAIT']))+waits,
        'transfers':max([s.get('transfers',0) for s in segments]),
        'notice':'Scheduled TheRide service; live delays, cancellations and fares are Unknown.' if mode=='BUS' else 'Current directional route estimates, not a future traffic forecast.'};
    if feed is not None { route['feed'] = {'version':feed['version'],'start_date':feed['start_date'],'end_date':feed['end_date'],'fetched_at':feed['fetched_at'],'source_url':feed['source_url']}; }
    return route;
}

def road_itinerary(stores: list, links: list, mode: str, context: dict, now: str, delivery: any = None) -> dict {
    zone = ZoneInfo(context['origin'].get('timezone') or get_settings()['timezone']);
    if mode=='WALK' and any([link['minutes'] > context['profile']['max_walk_min'] for link in links]) { raise ProviderError('A walking leg between stops exceeds your limit.'); }
    valid = min([instant(link['valid_until']) for link in links]);
    if valid <= instant(now) { raise ProviderError('A directional route estimate expired.'); }
    points = [context['origin'].get('address','Starting address')] + [s['name'] for s in stores] + [context['origin'].get('address','Starting address')];
    for (begin,finish) in trip_slots(context,now,delivery) {
        cursor = begin; segments = []; stops = []; good = True;
        for (index,link) in enumerate(links) {
            arrival = cursor + link['minutes']*60;
            start_text = datetime.fromtimestamp(cursor,zone).isoformat(); end_text = datetime.fromtimestamp(arrival,zone).isoformat();
            segments.append({'from':points[index],'to':points[index+1],'departure_at':start_text,'arrival_at':end_text,'minutes':link['minutes'], 'transfers':0,
                'legs':[{'kind':mode,'from':points[index],'to':points[index+1],'departure_at':start_text,'arrival_at':end_text,'minutes':link['minutes'],'source':'Geoapify directional route'}]});
            cursor = arrival;
            if index < len(stores) {
                store = stores[index]; store_zone = ZoneInfo(store.get('timezone') or str(zone));
                shopping = shop_start(cursor,store,store_zone);
                if shopping is None { good = False; break; }
                cursor = shopping + 1200;
                stops.append({'store_id':store['id'],'name':store['name'],'arrival_at':end_text,'shopping_at':datetime.fromtimestamp(shopping,store_zone).isoformat(),
                    'leave_at':datetime.fromtimestamp(cursor,store_zone).isoformat(),'wait_min':math.ceil((shopping-arrival)/60),'hours_known':weekly_hours(store.get('opening_hours','')) is not None});
            }
        }
        if good and cursor <= finish { return route_result(stores,segments,stops,mode,context,now,valid.isoformat()); }
    }
    raise ProviderError('No free-time window fits every travel leg, store hours, shopping stop and return, including delivery availability.');
}

def bus_itinerary(stores: list, context: dict, now: str, delivery: any = None) -> dict {
    feed = load_feed(); origin = context['origin']; profile = context['profile'];
    zone = ZoneInfo(origin.get('timezone') or feed['timezone']); points = [origin] + stores + [origin];
    walk_cache = {}; diagnostics = []; transfers = min(profile.get('max_transfers',1),2);
    (links,forbidden) = transfer_links(feed,profile['max_walk_min']) if transfers>0 else ({},set());
    refinements = 0;
    for (begin,finish) in trip_slots(context,now,delivery) {
        trips = timed_trips(feed,begin,finish); served = service_stops(feed,trips,begin,finish);
        if not served { diagnostics.append('No scheduled service overlaps a checked free-time window.'); continue; }
        cache_key = tuple(sorted(served));
        try {
            if cache_key not in walk_cache {
                walk_cache[cache_key] = [walking_links([p['lat'],p['lon']],served,profile['max_walk_min']) for p in points[:-1]];
            }
            walks = list(walk_cache[cache_key]); walks.append(walks[0]);
        } except ProviderError as error { diagnostics.append(str(error)); continue; }
        for attempt in range(12) {
            cursor = begin; journeys = []; stops = []; good = True;
            for index in range(len(points)-1) {
                target = stores[index] if index < len(stores) else None;
                hours = weekly_hours(target.get('opening_hours','')) if target is not None else None;
                target_zone = ZoneInfo(target.get('timezone') or feed['timezone']) if target is not None else zone;
                allowed = lambda arrival: float: store_allows(arrival,hours,target_zone) if target is not None else True;
                value = journey(feed,trips,walks[index][0],walks[index+1][1],links,forbidden,cursor,
                    finish-1200*(len(stores)-index) if target is not None else finish,transfers,
                    points[index].get('name',origin.get('address','Starting address')),points[index+1].get('name',origin.get('address','Starting address')),allowed);
                if value is None {
                    diagnostics.append('No scheduled connection fits segment '+str(index+1)+': '+points[index].get('name','Starting address')+' to '+points[index+1].get('name','Starting address')+' within the saved time, walking, transfer and store-hours constraints.');
                    good = False; break;
                }
                if index > 0 { stops[-1]['wait_min'] += math.ceil((value['departure']-cursor)/60); }
                journeys.append(value); cursor = value['arrival'];
                if target is not None {
                    cursor += 1200;
                    stops.append({'store_id':target['id'],'name':target['name'],'arrival_at':datetime.fromtimestamp(value['arrival'],target_zone).isoformat(),
                        'shopping_at':datetime.fromtimestamp(value['arrival'],target_zone).isoformat(),'leave_at':datetime.fromtimestamp(cursor,target_zone).isoformat(),'wait_min':0,'hours_known':hours is not None});
                }
            }
            if not good { break; }
            if verify_transfer_paths(journeys,links,feed,profile['max_walk_min']) {
                refinements += 1;
                if refinements>=12 { raise ProviderError('Multi-stop transit transfer verification reached its bounded limit.'); }
                continue;
            }
            segments = [present_journey(j,zone) for j in journeys];
            for (index,seg) in enumerate(segments) { seg['from']=points[index].get('name',origin.get('address','Starting address')); seg['to']=points[index+1].get('name',origin.get('address','Starting address')); }
            validity = [instant(now).timestamp()+900,instant(feed['fetched_at']).timestamp()+MAX_AGE];
            for seg in segments {
                for leg in seg['legs'] {
                    if leg.get('valid_until') { validity.append(instant(leg['valid_until']).timestamp()); }
                }
            }
            if min(validity)<=instant(now).timestamp() { raise ProviderError('A multi-stop walking connection expired.'); }
            return route_result(stores,segments,stops,'BUS',context,now,datetime.fromtimestamp(min(validity),zone).isoformat(),feed);
        }
    }
    raise ProviderError('No verified scheduled bus itinerary fits all stores and the return within your time, walking and transfer limits. '+' '.join(list(dict.fromkeys(diagnostics))[:3]));
}
