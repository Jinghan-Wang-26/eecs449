"""Issue #2 coverage matrix: which nearby stores have usable product evidence.

Collection reuses the app's own adapters, query parameters and matching rules,
so the matrix describes what CartCompass can actually find, not what a source
might offer in principle. Summaries are pure functions over a saved collection,
so a live run can be re-rendered or re-analysed offline.

Nothing is fabricated: a source that was not queried is reported as not run,
never as zero coverage, and a failed lookup is reported as an error.
"""
from __future__ import annotations
import time
from collections import Counter
from integrations import providers as api
from integrations.openprices import nearby_history, recommendation_records, CATEGORY_TAGS

# The ten demo categories; they include the README example (milk, eggs, rice, detergent).
DEFAULT_NEEDS = ['milk', 'eggs', 'rice', 'laundry detergent', 'dish soap',
                 'paper towels', 'yogurt', 'coffee', 'tofu', 'soy sauce']
# Public landmark used by earlier verification runs; never a personal address.
DEFAULT_ORIGIN = {'label': 'Michigan Union, 530 South State Street, Ann Arbor, MI 48109',
                  'lat': 42.2751698, 'lon': -83.7415127}
SOURCES = ('kroger', 'openprices', 'map')
FIELDS = ('package_size', 'weight', 'price', 'availability', 'fulfillment', 'timestamp')
LEGEND = {
    'C': 'current branch unit price and an in-stock/low-stock indication',
    'C?': 'current branch unit price, but stock unknown or out',
    'M': 'current match without a unit price (sold by weight or price missing)',
    'H': 'historical contributed record only (latest record date shown)',
    'U': 'candidate products returned, but none pass the app matching rules',
    '0': 'no candidate products found',
    'ERR': 'lookup failed (see collection JSON)',
    '-': 'not queried',
}


def _source(status, detail=''):
    return {'status': status, 'detail': detail}


def _osm_identity(store):
    kind = str(store.get('osm_type')).upper()
    return str(store.get('osm_id')), {'N': 'NODE', 'W': 'WAY', 'R': 'RELATION'}.get(kind, kind)


def _store_entry(store, kind):
    keys = ('id', 'external_id', 'name', 'address', 'lat', 'lon', 'source', 'distance_m',
            'price_count', 'source_url', 'osm_id', 'osm_type')
    return {**{k: store[k] for k in keys if k in store}, 'kind': kind, 'lookups': {}}


def kroger_lookup(store_id, term):
    """Same request as integrations.providers.products, plus raw fulfillment flags."""
    raw = api.kroger_get('products', {'filter.locationId': store_id, 'filter.term': term,
                                      'filter.fulfillment': 'ais', 'filter.limit': 10})
    rows = api.normalize_products(raw, store_id, term)
    flags = {}
    for product in raw.get('data', []):
        for item in product.get('items', []) or []:
            if isinstance(item, dict) and isinstance(item.get('fulfillment'), dict):
                key = f"kroger:{product.get('productId', '')}:{item.get('itemId', '')}"
                flags[key] = {k: v for k, v in item['fulfillment'].items() if isinstance(v, bool)}
    for row in rows:
        row['fulfillment'] = flags.get(row['key'], {})
    return rows


def _collect_kroger(result, needs, lat, lon, radius_m, limit, pause, log):
    found = api.nearby_kroger(lat, lon, radius_m)[:limit]
    result['sources']['kroger'] = _source('ok', f'{len(found)} branch(es) within radius queried.')
    for store in found:
        entry = _store_entry(store, 'current')
        for need in needs:
            try:
                entry['lookups'][need] = {'status': 'ok', 'rows': kroger_lookup(store['external_id'], need)}
            except api.ProviderError as error:
                entry['lookups'][need] = {'status': 'error', 'error': str(error)}
            time.sleep(pause)
        log(f"Kroger: {store.get('name', 'store')} checked")
        result['stores'].append(entry)


def _collect_openprices(result, needs, lat, lon, radius_m, limit, pause, log):
    nearby = nearby_history(lat, lon, radius_m)
    stores = nearby['stores']
    queried = sorted([s for s in stores if s.get('price_count', 0) > 0], key=lambda s: s['distance_m'])[:limit]
    detail = f'{len(stores)} contributed location(s) within radius; {len(queried)} with price records queried.'
    if nearby.get('truncated'):
        detail += ' Location list truncated at 100.'
    result['sources']['openprices'] = _source('ok', detail)
    for store in queried:
        entry = _store_entry(store, 'historical')
        # One bounded query set per store (recent records plus category tags), shared by all needs.
        try:
            evidence = recommendation_records(store['external_id'], needs)
            entry['records'], entry['partial'] = evidence['records'], evidence['partial']
            entry['lookups'] = {need: {'status': 'ok'} for need in needs}
        except api.ProviderError as error:
            entry['lookups'] = {need: {'status': 'error', 'error': str(error)} for need in needs}
        log(f"Open Prices: {store.get('name', 'store')} checked")
        result['stores'].append(entry)
        time.sleep(pause)
    result['stores'] += [_store_entry(s, 'location_only') for s in stores if s.get('price_count', 0) <= 0]


def _collect_map(result, lat, lon, radius_m):
    places = api.nearby_places(lat, lon, radius_m)
    # Same association rules as the app: retailer address evidence, then exact OSM identity.
    retailer = [{k: s[k] for k in ('lat', 'lon', 'address', 'name')}
                for s in result['stores'] if s['source'] == 'kroger']
    linked = {s['map_id'] for s in api.merge_stores(places, retailer) if s.get('map_id')}
    known_osm = {_osm_identity(s) for s in result['stores'] if s['source'] == 'openprices' and s.get('osm_id') is not None}
    unlinked = [p for p in places if p['id'] not in linked
                and not (p.get('osm_id') is not None and _osm_identity(p) in known_osm)]
    for place in unlinked:
        place = {**place, 'distance_m': round(api.distance_m((lat, lon), (place['lat'], place['lon'])))}
        result['stores'].append(_store_entry(place, 'map_only'))
    result['sources']['map'] = _source('ok', f'{len(places)} supermarket POI(s); {len(unlinked)} without a product source.')


def collect(needs=None, origin=None, radius_m=8000, max_kroger=5, max_openprices=5,
            sources=SOURCES, pause=0.1, now=None, log=print):
    """Query each enabled source near a public origin. Bounded and sequential."""
    needs = list(needs or DEFAULT_NEEDS)
    origin = dict(origin or DEFAULT_ORIGIN)
    lat, lon = api.coords(origin['lat'], origin['lon'])
    result = {'kind': 'Issue #2 coverage collection', 'checked_at': now or api.now_iso(),
              'origin': origin, 'radius_m': int(radius_m), 'needs': needs,
              'limits': {'max_kroger': max_kroger, 'max_openprices': max_openprices},
              'sources': {}, 'stores': []}
    flags = api.credential_status()
    steps = {
        'kroger': (flags['KROGER_CLIENT_ID'] and flags['KROGER_CLIENT_SECRET'],
                   'Configure KROGER_CLIENT_ID and KROGER_CLIENT_SECRET in the local .env.',
                   lambda: _collect_kroger(result, needs, lat, lon, radius_m, max_kroger, pause, log)),
        'openprices': (True, '',
                       lambda: _collect_openprices(result, needs, lat, lon, radius_m, max_openprices, pause, log)),
        # Runs last so it can drop supermarkets already linked to a product source.
        'map': (flags['GEOAPIFY_API_KEY'],
                'Configure GEOAPIFY_API_KEY to list supermarkets without product data.',
                lambda: _collect_map(result, lat, lon, radius_m)),
    }
    for name, (ready, missing, run) in steps.items():
        if name not in sources:
            result['sources'][name] = _source('skipped', 'Disabled for this run.')
        elif not ready:
            result['sources'][name] = _source('not_run', missing)
        else:
            try:
                run()
            except api.ProviderError as error:
                result['sources'][name] = _source('error', str(error))
    return result


def _matches(need, row, store, checked_at):
    # Imported lazily: these load the app's Jac policy modules.
    if store['kind'] == 'current':
        from planning.retail import suitable
        # Judge each quote at its own query time; freshness is not the coverage question.
        return suitable({'type': need, 'qty': 1}, row, store, [], row.get('observed_at', checked_at))
    from planning.visits import match_record
    return match_record({'type': need, 'qty': 1}, row, [], checked_at)


def _field_present(row, field, kind):
    if field == 'package_size':
        return bool(str(row.get('size_label') or '').strip())
    if field == 'weight':
        return row.get('weight_kg') is not None
    if field == 'price':
        return row.get('price') is not None
    if field == 'availability':
        return row.get('availability', 'UNKNOWN') != 'UNKNOWN'
    if field == 'fulfillment':
        return kind == 'current' and bool(row.get('fulfillment'))
    if field == 'timestamp':
        # Kroger rows carry only our query time; Open Prices records carry the contributor's date.
        if kind == 'historical':
            return row.get('recorded_on') not in (None, '', 'Unknown')
        return bool(row.get('observed_at'))
    raise ValueError(field)


def cell(need, store, checked_at):
    look = store['lookups'].get(need)
    if not look:
        return {'code': '-', 'returned': 0, 'matched': []}
    if look['status'] != 'ok':
        return {'code': 'ERR', 'returned': 0, 'matched': [], 'error': look.get('error', '')}
    if store['kind'] == 'current':
        rows = look.get('rows', [])
        matched = [r for r in rows if _matches(need, r, store, checked_at)]
        priced = [r for r in matched if r.get('price') is not None]
        stocked = [r for r in priced if r.get('availability') in ('IN_STOCK', 'LOW')]
        code = 'C' if stocked else 'C?' if priced else 'M' if matched else 'U' if rows else '0'
        return {'code': code, 'returned': len(rows), 'matched': matched}
    # Open Prices records are the store's recent/category records, not a per-need search.
    tag = CATEGORY_TAGS.get(need)
    candidates = [r for r in store.get('records', []) if tag and tag in r.get('categories', [])]
    matched = [r for r in store.get('records', []) if _matches(need, r, store, checked_at)]
    if matched:
        return {'code': 'H', 'returned': len(candidates), 'matched': matched,
                'latest': max(str(r.get('recorded_on', '')) for r in matched)}
    return {'code': 'U' if candidates else '0', 'returned': len(candidates), 'matched': []}


def summarize(collection):
    checked_at, needs = collection['checked_at'], collection['needs']
    product = [s for s in collection['stores'] if s['kind'] in ('current', 'historical')]
    matrix, completeness, examples, flags = {}, {}, {}, Counter()
    for store in product:
        matrix[store['id']] = {}
        stats = completeness.setdefault(store['source'], {'rows': 0, **{f: 0 for f in FIELDS}})
        for need in needs:
            c = cell(need, store, checked_at)
            matrix[store['id']][need] = {**{k: v for k, v in c.items() if k != 'matched'}, 'matched': len(c['matched'])}
            stats['rows'] += len(c['matched'])
            for row in c['matched']:
                for field in FIELDS:
                    stats[field] += _field_present(row, field, store['kind'])
                flags.update(k for k, v in (row.get('fulfillment') or {}).items() if v)
            group = examples.setdefault(need, [])
            for row in c['matched'][:2]:
                if len(group) < 6:
                    group.append({'store': store.get('name', ''), 'source': store['source'],
                                  'name': row.get('name', ''), 'size': row.get('size_label', ''),
                                  'price': row.get('price'), 'availability': row.get('availability', 'UNKNOWN'),
                                  'date': row.get('recorded_on') or row.get('observed_at', '')})
    by_need = {}
    for need in needs:
        codes = Counter(matrix[s['id']][need]['code'] for s in product)
        by_need[need] = {'current_in_stock': codes['C'], 'current_priced': codes['C'] + codes['C?'],
                         'current_unpriced': codes['M'], 'historical': codes['H'],
                         'unmatched': codes['U'], 'errors': codes['ERR']}
    gaps = [f"{name}: {s['status']} - {s['detail']}" for name, s in collection['sources'].items() if s['status'] != 'ok']
    def needs_where(test):
        return [n for n, v in by_need.items() if test(v)]
    if collection['sources'].get('kroger', {}).get('status') == 'ok':
        if missing := needs_where(lambda v: not v['current_in_stock']):
            gaps.append('No current in-stock match at any queried branch: ' + ', '.join(missing))
    if missing := needs_where(lambda v: not (v['current_priced'] or v['historical'])):
        gaps.append('No price evidence from any queried source: ' + ', '.join(missing))
    if missing := needs_where(lambda v: v['unmatched']):
        gaps.append('Candidates returned but rejected by the app matching rules (review terms/rules): ' + ', '.join(missing))
    if missing := needs_where(lambda v: v['errors']):
        gaps.append('Lookup errors (rerun before drawing conclusions): ' + ', '.join(missing))
    if unlisted := [s for s in collection['stores'] if s['kind'] in ('map_only', 'location_only')]:
        gaps.append(f'{len(unlisted)} nearby store(s) have no product evidence; the app can offer them only as location-only visits.')
    return {'kind': 'Issue #2 coverage summary', 'checked_at': checked_at, 'origin': collection['origin'],
            'radius_m': collection['radius_m'], 'needs': needs, 'sources': collection['sources'],
            'stores': [{k: s[k] for k in ('id', 'name', 'address', 'source', 'kind', 'distance_m') if k in s}
                       for s in collection['stores']],
            'matrix': matrix, 'by_need': by_need, 'field_completeness': completeness,
            'fulfillment_flags': dict(flags), 'examples': examples, 'gaps': gaps, 'legend': LEGEND}


def _pct(part, whole):
    return f'{part}/{whole} ({round(100 * part / whole)}%)' if whole else 'n/a'


def render_markdown(summary):
    lines = [f"# Coverage matrix: {summary['origin'].get('label', 'origin')}", '',
             f"Checked {summary['checked_at']} within {summary['radius_m']} m. Generated by "
             '`scripts/coverage_matrix.py`; product rows are judged with the app matching rules.', '',
             '## Sources', '', '| Source | Status | Detail |', '|---|---|---|']
    lines += [f"| {name} | {s['status']} | {s['detail']} |" for name, s in summary['sources'].items()]
    product = [s for s in summary['stores'] if s['kind'] in ('current', 'historical')]
    lines += ['', '## Need x store matrix', '']
    if product:
        lines.append('| Need | ' + ' | '.join(f"{s['name']} ({s['source']}, {s.get('distance_m', '?')} m)"
                                             for s in product) + ' |')
        lines.append('|---' * (len(product) + 1) + '|')
        for need in summary['needs']:
            cells = []
            for s in product:
                c = summary['matrix'][s['id']][need]
                text = c['code'] + (f" ({c['matched']})" if c['matched'] else '')
                cells.append(text + (f" {c['latest']}" if c['code'] == 'H' else ''))
            lines.append(f'| {need} | ' + ' | '.join(cells) + ' |')
    else:
        lines.append('No store with a product source was queried.')
    lines += ['', 'Legend: ' + '; '.join(f'`{k}` {v}' for k, v in summary['legend'].items()) + '.',
              'Counts in parentheses are matched product variants.', '',
              '## Field completeness of matched rows', '',
              '| Source | Matched rows | ' + ' | '.join(FIELDS) + ' |', '|---' * (len(FIELDS) + 2) + '|']
    for source, stats in summary['field_completeness'].items():
        lines.append(f"| {source} | {stats['rows']} | " + ' | '.join(_pct(stats[f], stats['rows']) for f in FIELDS) + ' |')
    if not summary['field_completeness']:
        lines.append('| (none) | 0 | ' + ' | '.join('n/a' for _ in FIELDS) + ' |')
    if summary['fulfillment_flags']:
        lines += ['', 'Kroger fulfillment flags set on matched items: ' +
                  ', '.join(f'{k}={v}' for k, v in sorted(summary['fulfillment_flags'].items())) + '.']
    if other := [s for s in summary['stores'] if s['kind'] in ('map_only', 'location_only')]:
        lines += ['', '## Stores without product evidence', '', '| Store | Kind | Distance (m) |', '|---|---|---|']
        lines += [f"| {s['name']} | {s['kind']} | {s.get('distance_m', '?')} |" for s in other]
    lines += ['', '## Gaps found by this run', '']
    lines += [f'- {g}' for g in summary['gaps']] or ['- None detected.']
    lines += ['', '## Match review samples', '', 'Check these by hand: a name match is not proof that the product meets the need.', '']
    for need, rows in summary['examples'].items():
        for r in rows:
            price = 'unknown' if r['price'] is None else f"${r['price']}"
            lines.append(f"- **{need}**: {r['name']} {r['size']} - {price}, {r['availability']} "
                         f"({r['store']}, {r['source']}, {str(r['date'])[:10]})")
    if not any(summary['examples'].values()):
        lines.append('- No matched products to review.')
    return '\n'.join(lines) + '\n'
