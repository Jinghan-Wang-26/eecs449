"""Geoapify and Kroger adapters. Credentials stay on the server.

Responses are normalized with provenance. Missing prices, inventory, weight,
transit service and delivery fees remain unknown. No mock fallback is allowed.
"""
from __future__ import annotations
import base64
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

class ProviderError(ValueError):
    pass

ROOT = Path(__file__).resolve().parent.parent
_CACHE = {}
_LOCK = threading.Lock()
_TOKEN = {"value": "", "expires": 0, "identity": ""}

def credentials():
    values = {}
    path = ROOT / '.env'
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.removeprefix('export ').split('=', 1)
            values[key.strip()] = value.strip().strip('\"\'')
    for key in ('KROGER_CLIENT_ID', 'KROGER_CLIENT_SECRET', 'GEOAPIFY_API_KEY',
                'LLM_API_KEY', 'LLM_BASE_URL', 'LLM_MODEL', 'LLM_BACKEND'):
        if key in os.environ:
            values[key] = os.environ[key]
    return values

def credential_status():
    values = credentials()
    return {key: bool(values.get(key)) for key in
            ('KROGER_CLIENT_ID', 'KROGER_CLIENT_SECRET', 'GEOAPIFY_API_KEY', 'LLM_API_KEY')}

def required(name):
    value = credentials().get(name, '')
    if not value:
        raise ProviderError(f'Missing {name}. Configure it in the local .env and retry.')
    return value

def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')

def expiry(minutes=30):
    return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat(timespec='seconds')

def request_json(url, *, params=None, headers=None, body=None, form=False):
    if params:
        url += '?' + urllib.parse.urlencode(params)
    data = None
    hdr = {'Accept': 'application/json', 'User-Agent': 'CartCompass/0.2 (course shopping prototype)'}
    if body is not None:
        data = (urllib.parse.urlencode(body) if form else json.dumps(body)).encode()
        hdr['Content-Type'] = 'application/x-www-form-urlencoded' if form else 'application/json'
    hdr.update(headers or {})
    for attempt in range(2):
        req = urllib.request.Request(url, data=data, headers=hdr)
        try:
            with urllib.request.urlopen(req, timeout=12) as response:
                raw = response.read(2_000_001)
                if len(raw) > 2_000_000:
                    raise ProviderError('Provider response exceeded the size limit.')
                return json.loads(raw)
        except urllib.error.HTTPError as err:
            if data is None and err.code in (429, 502, 503, 504) and attempt == 0:
                time.sleep(1)
                continue
            # Do not return response bodies, request URLs, addresses, or tokens.
            detail = {401: 'credentials rejected', 403: 'access not granted',
                      429: 'rate limit reached'}.get(err.code, 'request failed')
            raise ProviderError(f'Provider {detail} (HTTP {err.code}).') from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise ProviderError('Provider unavailable or timed out. Retry later; no live data was replaced with mock data.') from None
        except (ValueError, KeyError, TypeError):
            raise ProviderError('Provider returned an invalid JSON response.') from None

def cached(namespace, params, fetch, ttl=300):
    identity = hashlib.sha256(json.dumps([namespace, params], sort_keys=True).encode()).hexdigest()
    with _LOCK:
        found = _CACHE.get(identity)
        if found and found[0] > time.monotonic():
            return copy.deepcopy(found[1])
    value = fetch()
    with _LOCK:
        if len(_CACHE) >= 128:
            _CACHE.pop(next(iter(_CACHE)))
        _CACHE[identity] = (time.monotonic() + ttl, copy.deepcopy(value))
    return value

def coords(lat, lon):
    lat, lon = float(lat), float(lon)
    if not math.isfinite(lat) or not math.isfinite(lon) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ProviderError('Invalid coordinates.')
    return lat, lon

def geocode(address):
    if not isinstance(address, str) or not 3 <= len(address.strip()) <= 300:
        raise ProviderError('Enter an address or neighborhood (3–300 characters).')
    key = required('GEOAPIFY_API_KEY')
    def fetch():
        data = request_json('https://api.geoapify.com/v1/geocode/search', params={
            'text': address.strip(), 'filter': 'countrycode:us', 'format': 'json', 'limit': 5, 'apiKey': key})
        out = []
        for p in data.get('results', []):
            lat, lon = coords(p['lat'], p['lon'])
            out.append({'id': p.get('place_id') or f'{lat},{lon}', 'address': p.get('formatted', address),
                        'lat': lat, 'lon': lon, 'precision': p.get('result_type', 'unknown'),
                        'confidence': p.get('rank', {}).get('confidence'), 'source': 'geoapify'})
        return out
    return cached('geocode', [address, key], fetch, 86400)

def nearby_places(lat, lon, radius_m=5000):
    lat, lon = coords(lat, lon)
    key = required('GEOAPIFY_API_KEY')
    radius_m = max(500, min(int(radius_m), 20000))
    def fetch():
        data = request_json('https://api.geoapify.com/v2/places', params={
            'categories': 'commercial.supermarket', 'filter': f'circle:{lon},{lat},{radius_m}',
            'bias': f'proximity:{lon},{lat}', 'limit': 20, 'apiKey': key})
        return [{'id': f"geoapify:{f['properties']['place_id']}",
                 'name': f['properties'].get('name', 'Supermarket'),
                 'address': f['properties'].get('formatted', ''),
                 'lat': f['properties']['lat'], 'lon': f['properties']['lon'],
                 'source': 'geoapify', 'product_access': False,
                 'osm_id': f['properties'].get('datasource', {}).get('raw', {}).get('osm_id'),
                 'osm_type': f['properties'].get('datasource', {}).get('raw', {}).get('osm_type')}
                for f in data.get('features', [])]
    return cached('places', [lat, lon, radius_m, key], fetch, 900)

def kroger_token():
    client, secret = required('KROGER_CLIENT_ID'), required('KROGER_CLIENT_SECRET')
    identity = hashlib.sha256((client + ':' + secret).encode()).hexdigest()
    with _LOCK:
        if _TOKEN['identity'] == identity and _TOKEN['expires'] > time.monotonic():
            return _TOKEN['value']
    basic = base64.b64encode((client + ':' + secret).encode()).decode()
    data = request_json('https://api.kroger.com/v1/connect/oauth2/token',
                        headers={'Authorization': 'Basic ' + basic},
                        body={'grant_type': 'client_credentials', 'scope': 'product.compact'}, form=True)
    if not isinstance(data.get('access_token'), str):
        raise ProviderError('Kroger did not return an access token.')
    with _LOCK:
        _TOKEN.update(value=data['access_token'], identity=identity,
                      expires=time.monotonic() + max(0, float(data.get('expires_in', 0)) - 60))
    return data['access_token']

def kroger_get(path, params):
    return request_json('https://api.kroger.com/v1/' + path, params=params,
                        headers={'Authorization': 'Bearer ' + kroger_token()})

def hours_for(hours):
    out = {}
    for name, day in hours.items():
        if not isinstance(day, dict) or day.get('isClosed'):
            continue
        opening, closing = day.get('open', ''), day.get('close', '')
        if re.fullmatch(r'\d\d:\d\d', opening) and re.fullmatch(r'\d\d:\d\d', closing) and opening < closing:
            out[name[:3].upper()] = opening + '-' + closing
    return out

def distance_m(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))

def nearby_kroger(lat, lon, radius_m=5000):
    lat, lon = coords(lat, lon)
    data = kroger_get('locations', {'filter.latLong.near': f'{lat},{lon}',
          'filter.radiusInMiles': max(1, min(50, math.ceil(radius_m / 1609.344))), 'filter.limit': 10})
    out = []
    for p in data.get('data', []):
        geo, addr = p.get('geolocation', {}), p.get('address', {})
        if geo.get('latitude') is None or geo.get('longitude') is None:
            continue
        slat, slon = coords(geo['latitude'], geo['longitude'])
        dist = distance_m((lat, lon), (slat, slon))
        if dist > radius_m:
            continue
        out.append({'id': 'kroger:' + p['locationId'], 'external_id': p['locationId'],
                    'name': p.get('name', 'Kroger'), 'address': ', '.join(str(addr.get(k, '')) for k in
                    ('addressLine1', 'city', 'state', 'zipCode')), 'lat': slat, 'lon': slon,
                    'hours': hours_for(p.get('hours', {})), 'source': 'kroger', 'product_access': True,
                    'distance_m': round(dist), 'observed_at': now_iso()})
    return sorted(out, key=lambda s: s['distance_m'])

def merge_stores(places, retailer):
    # Retailer locations are authoritative. Associate POIs only with spatial AND
    # street-number evidence; uncertain matches remain independent, unsupported POIs.
    merged = copy.deepcopy(retailer)
    for place in places:
        candidates = [s for s in merged if distance_m((s['lat'], s['lon']), (place['lat'], place['lon'])) < 100
                      and re.findall(r'^\d+', s['address']) and
                      re.findall(r'^\d+', s['address']) == re.findall(r'^\d+', place['address'])
                      and ('kroger' in place['name'].lower() or s['name'].lower() == place['name'].lower())]
        if len(candidates) == 1:
            candidates[0]['map_id'] = place['id']
        else:
            merged.append(place)
    return merged

def nearby(lat, lon, radius_m=5000):
    stores, notices = [], []
    try:
        stores = nearby_places(lat, lon, radius_m)
    except ProviderError as exc:
        notices.append(str(exc))
    try:
        stores = merge_stores(stores, nearby_kroger(lat, lon, radius_m))
    except ProviderError as exc:
        notices.append(str(exc))
    return {'stores': stores, 'notices': notices}

def weight_from_size(size):
    match = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*(kg|g|lb|lbs|oz)\s*', size or '', re.I)
    if not match:
        return None
    return round(float(match[1]) * {'kg': 1, 'g': .001, 'lb': .45359237, 'lbs': .45359237, 'oz': .028349523125}[match[2].lower()], 4)

def normalize_products(data, store_id, term, observed=None):
    observed = observed or now_iso()
    expires = (datetime.fromisoformat(observed) + timedelta(minutes=30)).isoformat()
    out = []
    for p in data.get('data', []):
        for item in p.get('items', []):
            price = item.get('price') or {}
            value = price.get('regular')
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                value = None
            stock = (item.get('inventory') or {}).get('stockLevel', '')
            stock = {'HIGH': 'IN_STOCK', 'LOW': 'LOW', 'TEMPORARILY_OUT_OF_STOCK': 'OUT', 'OUT_OF_STOCK': 'OUT'}.get(stock, 'UNKNOWN')
            size = item.get('size', '')
            product_id = str(p.get('productId', ''))
            item_id = str(item.get('itemId', ''))
            if not product_id or not item_id:
                continue
            out.append({'key': f'kroger:{product_id}:{item_id}', 'external_id': product_id, 'item_id': item_id,
                        'name': p.get('description', ''), 'brand': p.get('brand', ''), 'upc': p.get('upc', ''),
                        'size_label': size, 'weight_kg': weight_from_size(size),
                        'store_id': store_id, 'search_term': term, 'price': value,
                        'promotion': price.get('promo'), 'currency': 'USD', 'availability': stock,
                        'in_store': (item.get('fulfillment') or {}).get('inStore') is True,
                        'source': 'kroger', 'mode': 'live', 'observed_at': observed, 'valid_until': expires})
    return out

def products(store_id, term):
    if not isinstance(store_id, str) or not re.fullmatch(r'\d{1,20}', store_id):
        raise ProviderError('Select a supported Kroger location first.')
    if not isinstance(term, str) or not 2 <= len(term.strip()) <= 80:
        raise ProviderError('Enter a product search term (2–80 characters).')
    # Credential check precedes cache access, so removal of credentials takes effect.
    identity = required('KROGER_CLIENT_ID')
    required('KROGER_CLIENT_SECRET')
    return cached('products', [store_id, term, identity], lambda: normalize_products(
        kroger_get('products', {'filter.locationId': store_id, 'filter.term': term,
                               'filter.fulfillment': 'inStore', 'filter.limit': 5}), store_id, term), 300)

def route(origin, destination, mode):
    modes = {'WALK': 'walk', 'BIKE': 'bicycle', 'CAR': 'drive'}
    if mode not in modes:
        raise ProviderError(f'{mode} route estimates are not available from this adapter. Bus vehicle routing is not public-transit routing.')
    a, b = coords(*origin), coords(*destination)
    key = required('GEOAPIFY_API_KEY')
    def fetch():
        # Request each direction; one-way roads can change the return trip.
        legs = []
        for start, end in ((a, b), (b, a)):
            data = request_json('https://api.geoapify.com/v1/routing', params={
                'waypoints': f'{start[0]},{start[1]}|{end[0]},{end[1]}', 'mode': modes[mode], 'apiKey': key})
            if not data.get('features'):
                raise ProviderError('No route found for this transport mode.')
            legs.append(data['features'][0]['properties'])
        minutes = math.ceil(sum(x['time'] for x in legs) / 60)
        return {'min': minutes, 'walk_min': math.ceil(max(x['time'] for x in legs) / 60) if mode == 'WALK' else 0,
                'distance_m': sum(x['distance'] for x in legs), 'cost': 0 if mode in ('WALK', 'BIKE') else None,
                'transfers': 0, 'source': 'geoapify', 'observed_at': now_iso(), 'valid_until': expiry(60)}
    return cached('route', [a, b, mode, key], fetch, 900)


def reverse_geocode(lat, lon, accuracy_m=0):
    lat, lon = coords(lat, lon)
    accuracy_m = float(accuracy_m)
    if not math.isfinite(accuracy_m) or not 0 <= accuracy_m <= 100000:
        raise ProviderError('Invalid location accuracy.')
    key = required('GEOAPIFY_API_KEY')
    data = cached('reverse', [lat, lon, key], lambda: request_json(
        'https://api.geoapify.com/v1/geocode/reverse', params={'lat':lat, 'lon':lon, 'format':'json', 'limit':1, 'apiKey':key}), 900)
    rows = data.get('results', [])
    if not rows:
        raise ProviderError('No address found for this location. Please type an address instead.')
    row = rows[0]
    # Keep actual device coordinates, not a possibly distant reverse-geocoded centroid.
    return [{'id': f'gps:{lat:.6f}:{lon:.6f}', 'lat':lat, 'lon':lon,
             'address':row.get('formatted') or f'{lat:.5f}, {lon:.5f}', 'precision':'device location',
             'accuracy_m':accuracy_m, 'source':'geoapify'}]
