"""TheRide GTFS transport adapter. Schedule rules and journey search live in Jac.

Download public timetable data on demand, at most once per day. Never serve a
stale cache after a refresh failure, or convert a timetable into a live prediction.
"""
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import urllib.request
import zipfile

from integrations.providers import ProviderError, distance_m, route

FEED_URL = 'https://www.theride.org/sites/default/files/google/google_transit.zip'
SOURCE_URL = 'https://www.theride.org/business/software-developers'
CACHE_DIR = Path(__file__).resolve().parents[1] / '.jac' / 'transit'
MAX_AGE = 24 * 3600
_LOCK = threading.Lock()
_MEMORY = None


def read_feed(raw, fetched_at):
    """Parse only needed CSV members, never extract a ZIP into the filesystem."""
    try:
        archive = zipfile.ZipFile(io.BytesIO(raw))
        def rows(name, required=False):
            if name not in archive.namelist():
                if required:
                    raise ValueError('Missing ' + name)
                return []
            info = archive.getinfo(name)
            if info.file_size > 32_000_000:
                raise ValueError('GTFS member exceeds size limit')
            with archive.open(name) as handle:
                return list(csv.DictReader(io.TextIOWrapper(handle, encoding='utf-8-sig')))
        agencies = rows('agency.txt', True)
        if len(agencies) != 1 or agencies[0]['agency_timezone'] != 'America/New_York':
            raise ValueError('Expected a single TheRide agency in America/New_York')
        metadata = rows('feed_info.txt', True)[0]
        for field in ('feed_start_date', 'feed_end_date'):
            datetime.strptime(metadata[field], '%Y%m%d')
        stops = {}
        for row in rows('stops.txt', True):
            if row.get('location_type', '') not in ('', '0'):
                continue
            lat, lon = float(row['stop_lat']), float(row['stop_lon'])
            if not (math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180):
                raise ValueError('Invalid stop coordinates')
            stops[row['stop_id']] = {'id':row['stop_id'], 'name':row['stop_name'],
                'code':row.get('stop_code') or row['stop_id'], 'lat':lat, 'lon':lon}
        routes = {r['route_id']:r for r in rows('routes.txt', True) if r['route_type'] == '3'}
        frequency_trips = {r['trip_id'] for r in rows('frequencies.txt')}
        trips = {r['trip_id']:{**r, 'route_name':routes[r['route_id']]['route_short_name'] or routes[r['route_id']]['route_long_name'], 'stops':[]}
                 for r in rows('trips.txt', True) if r['route_id'] in routes and r['trip_id'] not in frequency_trips}
        invalid = set()
        def seconds(value):
            h, m, s = map(int, value.split(':'))
            if not (0 <= h < 48 and 0 <= m < 60 and 0 <= s < 60):
                raise ValueError('Unsupported GTFS time')
            return h * 3600 + m * 60 + s
        for row in rows('stop_times.txt', True):
            key = row['trip_id']
            if key not in trips:
                continue
            try:
                arrival, departure = seconds(row['arrival_time']), seconds(row['departure_time'])
                if row['stop_id'] not in stops or departure < arrival:
                    raise ValueError('Invalid stop/time')
                trips[key]['stops'].append({'stop':row['stop_id'], 'arr':arrival, 'dep':departure,
                    'seq':int(row['stop_sequence']), 'pickup':row.get('pickup_type', '') in ('', '0'),
                    'dropoff':row.get('drop_off_type', '') in ('', '0')})
            except (ValueError, KeyError):
                invalid.add(key)
        for key, trip in trips.items():
            trip['stops'].sort(key=lambda x:x['seq'])
            if len(trip['stops']) < 2 or any(a['dep'] > b['arr'] or a['seq'] >= b['seq'] for a,b in zip(trip['stops'],trip['stops'][1:])):
                invalid.add(key)
        for key in invalid:
            trips.pop(key, None)
        transfers = rows('transfers.txt')
        for row in transfers:
            # Fail closed if a future feed needs route/trip-specific precedence.
            if any(row.get(k) for k in ('from_trip_id','to_trip_id','from_route_id','to_route_id')):
                raise ValueError('Trip-specific transfer rules are not supported yet')
            if row['from_stop_id'] not in stops or row['to_stop_id'] not in stops or row.get('transfer_type','0') not in ('','0','1','2','3'):
                raise ValueError('Unsupported transfer rule')
            row['min_seconds'] = int(row.get('min_transfer_time') or 0)
            if row['min_seconds'] < 0 or (row.get('transfer_type') == '2' and not row.get('min_transfer_time')):
                raise ValueError('Invalid minimum transfer time')
        calendar = rows('calendar.txt')
        exceptions = rows('calendar_dates.txt')
        if not trips or not (calendar or exceptions):
            raise ValueError('Feed has no supported scheduled bus trips')
        return {'stops':stops, 'trips':list(trips.values()), 'calendar':calendar,
            'exceptions':exceptions, 'transfers':transfers, 'timezone':'America/New_York',
            'start_date':metadata['feed_start_date'], 'end_date':metadata['feed_end_date'],
            'version':metadata.get('feed_version',''), 'fingerprint':hashlib.sha256(raw).hexdigest(),
            'fetched_at':fetched_at, 'source_url':SOURCE_URL, 'feed_url':FEED_URL,
            'skipped_trips':len(invalid) + len(frequency_trips)}
    except (ValueError, KeyError, IndexError, UnicodeError, zipfile.BadZipFile, csv.Error) as error:
        raise ProviderError('TheRide timetable is invalid or unsupported: ' + str(error)) from None


def _download():
    request = urllib.request.Request(FEED_URL, headers={'User-Agent':'CartCompass/1.0 (course shopping planner)'})
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            raw = response.read(15_000_001)
        if len(raw) > 15_000_000:
            raise ValueError('File exceeds download limit')
        return raw
    except (OSError, ValueError) as error:
        raise ProviderError('TheRide timetable download failed. Retry later; stale schedules are not used.') from None


def load_feed():
    global _MEMORY
    with _LOCK:
        current = time.time()
        if _MEMORY and 0 <= current - _MEMORY[0] < MAX_AGE:
            return _MEMORY[1]
        archive, meta = CACHE_DIR / 'theride.zip', CACHE_DIR / 'theride.json'
        try:
            saved = json.loads(meta.read_text())
            fetched = float(saved['fetched_epoch'])
            raw = archive.read_bytes()
            if not (0 <= current - fetched < MAX_AGE) or hashlib.sha256(raw).hexdigest() != saved['sha256']:
                raise ValueError('Expired or mismatched cache')
            feed = read_feed(raw, datetime.fromtimestamp(fetched, timezone.utc).isoformat())
        except (OSError, ValueError, KeyError, TypeError, ProviderError):
            raw = _download()
            fetched = time.time()
            feed = read_feed(raw, datetime.fromtimestamp(fetched, timezone.utc).isoformat())
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            temp_zip = archive.with_suffix('.zip.tmp')
            temp_meta = meta.with_suffix('.json.tmp')
            temp_zip.write_bytes(raw)
            temp_meta.write_text(json.dumps({'fetched_epoch':fetched, 'sha256':hashlib.sha256(raw).hexdigest()}))
            os.replace(temp_zip, archive)
            os.replace(temp_meta, meta)
        _MEMORY = (fetched, feed)
        return feed


def walking_links(point, stops, maximum):
    """Verify both access directions for at most eight supplied stops within 1.2 km.

    Callers supply stops served during the selected service window."""
    nearby = sorted(((distance_m(point, (s['lat'],s['lon'])), s) for s in stops.values()), key=lambda x:(x[0],x[1]['id']))
    nearby = [(d,s) for d,s in nearby if d <= min(1200, maximum * 90)][:8]
    if not nearby:
        raise ProviderError('No TheRide stop with service in this window is within the bounded 1.2 km access search and your walking limit. Coverage is Ann Arbor/Ypsilanti only.')
    def verify(pair):
        _, stop = pair
        try:
            result = route(point, [stop['lat'],stop['lon']], 'WALK')
            return stop['id'], result
        except ProviderError:
            return stop['id'], None
    toward, away = {}, {}
    with ThreadPoolExecutor(max_workers=3) as pool:
        for key, result in pool.map(verify, nearby):
            if not result:
                continue
            for minutes, output in ((result['outbound_min'], toward),(result['return_min'], away)):
                if minutes <= maximum:
                    output[key] = {'seconds':int(minutes * 60), 'source':'Geoapify walking route', 'valid_until':result['valid_until']}
    if not toward or not away:
        raise ProviderError('No verified walking connection to TheRide stops fits your limit. Check your walking limit or retry the map provider.')
    return toward, away


def transfer_links(feed, maximum):
    """Candidate platform connections, verified lazily before a plan is offered.

    Only four neighbours within 150 m per stop, plus explicit GTFS pairs. Zero
    provisional walking time is a search lower bound, never a displayed estimate.
    """
    links, forbidden = {}, set()
    stops = feed['stops']
    for rule in feed['transfers']:
        if rule.get('transfer_type') == '3':
            forbidden.add((rule['from_stop_id'],rule['to_stop_id']))
    for a,start in stops.items():
        nearby = sorted(((distance_m((start['lat'],start['lon']),(end['lat'],end['lon'])),b)
                         for b,end in stops.items() if a != b), key=lambda x:(x[0],x[1]))
        for distance,b in [p for p in nearby if p[0] <= min(150, maximum * 90)][:4]:
            if (a,b) not in forbidden:
                links.setdefault(a,{})[b] = {'seconds':0, 'min_seconds':0, 'verified':False,
                    'transfer_from':a, 'transfer_to':b, 'source':'Unverified candidate platform connection'}
    for rule in feed['transfers']:
        a,b = rule['from_stop_id'],rule['to_stop_id']
        if (a,b) in forbidden:
            continue
        links.setdefault(a,{})[b] = {'seconds':0, 'min_seconds':rule['min_seconds'],
            'verified':a == b, 'transfer_from':a, 'transfer_to':b, 'source':'GTFS same-stop connection' if a == b else 'Unverified GTFS transfer'}
    return links, forbidden


def verify_transfer_paths(journeys, links, feed, maximum):
    """Replace provisional footpaths with actual routes, or remove failed edges.

    Return True when search must run again. Callers cannot publish a journey
    while any selected footpath remains provisional.
    """
    changed = False
    pairs = {(leg['transfer_from'],leg['transfer_to']) for journey in journeys
             for leg in journey['legs'] if not leg.get('verified', True)}
    for a,b in sorted(pairs):
        value = links.get(a,{}).get(b)
        if value is None or value.get('verified', True):
            continue
        changed = True
        start,end = feed['stops'][a],feed['stops'][b]
        try:
            result = route([start['lat'],start['lon']],[end['lat'],end['lon']], 'WALK')
            if result['outbound_min'] > maximum:
                raise ProviderError('Transfer walk exceeds the limit')
            value.update(seconds=int(result['outbound_min'] * 60), verified=True,
                         source='Geoapify verified platform walk', valid_until=result['valid_until'])
        except ProviderError:
            del links[a][b]
    return changed
