"""Issue #2 coverage matrix: all provider data here is SYNTHETIC, not live evidence."""
import copy
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch
import jaclang  # noqa: F401  The matrix uses the app's Jac matching rules.
from integrations import coverage
from integrations import providers as api

NOW = '2026-10-31T12:00:00+00:00'
LATER = '2026-10-31T12:30:00+00:00'


def quote(name, price=3.0, stock='IN_STOCK', size='1 gal', **extra):
    return {'key': f'kroger:{name}:01', 'external_id': name, 'item_id': '01', 'store_id': '1',
            'source': 'kroger', 'mode': 'live', 'name': name, 'brand': 'Test', 'size_label': size,
            'weight_kg': None, 'price': price, 'sold_by': 'unit', 'availability': stock, 'in_store': True,
            'fulfillment': {'inStore': True, 'delivery': True, 'curbside': False},
            'observed_at': NOW, 'valid_until': LATER, **extra}


def record(name, tag, day='2025-05-01', size='1 L'):
    return {'record_id': hash(name) % 1000, 'name': name, 'brand': '', 'size_label': size, 'weight_kg': None,
            'price': 2.5, 'availability': 'UNKNOWN', 'recorded_on': day, 'categories': [tag], 'labels': [],
            'source': 'openprices', 'data_kind': 'historical'}


KROGER = {'id': 'kroger:1', 'external_id': '1', 'name': 'Synthetic Kroger', 'address': '100 Test St',
          'lat': 42.0, 'lon': -83.0, 'source': 'kroger', 'distance_m': 900, 'kind': 'current', 'lookups': {
              'milk': {'status': 'ok', 'rows': [quote('Whole Milk')]},
              'rice': {'status': 'ok', 'rows': [quote('Rice Cakes', size='4 oz')]},
              'eggs': {'status': 'ok', 'rows': [quote('Large Eggs', stock='UNKNOWN', size='12 ct')]},
              'coffee': {'status': 'ok', 'rows': [quote('Ground Coffee', price=None, sold_by='weight')]},
              'yogurt': {'status': 'ok', 'rows': []},
              'tofu': {'status': 'error', 'error': 'Provider rate limit reached (HTTP 429).'}}}
OPEN = {'id': 'openprices:7', 'external_id': '7', 'name': 'Synthetic Market', 'address': '200 Test St',
        'source': 'openprices', 'distance_m': 1500, 'kind': 'historical', 'partial': False,
        'records': [record('Whole Milk', 'en:milks'), record('Chocolate Milk', 'en:milks', '2025-06-01'),
                    record('Chocolate Eggs', 'en:eggs')],
        'lookups': {n: {'status': 'ok'} for n in ('milk', 'rice', 'eggs')}}
MAP_ONLY = {'id': 'geoapify:x', 'name': 'Synthetic Grocer', 'source': 'geoapify', 'distance_m': 2000,
            'kind': 'map_only', 'lookups': {}}
COLLECTION = {'kind': 'Issue #2 coverage collection', 'checked_at': NOW, 'radius_m': 8000,
              'origin': {'label': 'Synthetic public origin', 'lat': 42.0, 'lon': -83.0},
              'needs': ['milk', 'rice', 'eggs', 'coffee', 'yogurt', 'tofu', 'soy sauce'],
              'sources': {'kroger': {'status': 'ok', 'detail': ''}, 'openprices': {'status': 'ok', 'detail': ''},
                          'map': {'status': 'ok', 'detail': ''}},
              'stores': [KROGER, OPEN, MAP_ONLY]}


def silent(*_):
    return None


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.summary = coverage.summarize(copy.deepcopy(COLLECTION))

    def code(self, store, need):
        return self.summary['matrix'][store][need]['code']

    def test_current_codes_follow_app_matching_and_never_infer_stock(self):
        self.assertEqual(self.code('kroger:1', 'milk'), 'C')
        self.assertEqual(self.code('kroger:1', 'eggs'), 'C?')      # priced, stock unknown
        self.assertEqual(self.code('kroger:1', 'coffee'), 'M')     # matched, no unit price
        self.assertEqual(self.code('kroger:1', 'rice'), 'U')       # rice cakes are excluded by the app
        self.assertEqual(self.code('kroger:1', 'yogurt'), '0')
        self.assertEqual(self.code('kroger:1', 'tofu'), 'ERR')
        self.assertEqual(self.code('kroger:1', 'soy sauce'), '-')  # never reported as zero coverage

    def test_historical_codes_use_latest_matching_record_only(self):
        milk = self.summary['matrix']['openprices:7']['milk']
        self.assertEqual((milk['code'], milk['matched'], milk['latest']), ('H', 1, '2025-05-01'))
        self.assertEqual(self.code('openprices:7', 'eggs'), 'U')   # tagged, but excluded by name rules
        self.assertEqual(self.code('openprices:7', 'rice'), '0')
        self.assertEqual(self.code('openprices:7', 'coffee'), '-')

    def test_field_completeness_counts_matched_rows(self):
        kroger = self.summary['field_completeness']['kroger']
        self.assertEqual(kroger['rows'], 3)
        self.assertEqual((kroger['price'], kroger['availability'], kroger['fulfillment']), (2, 2, 3))
        history = self.summary['field_completeness']['openprices']
        self.assertEqual((history['rows'], history['availability'], history['fulfillment'], history['timestamp']), (1, 0, 0, 1))
        self.assertEqual(self.summary['fulfillment_flags'], {'inStore': 3, 'delivery': 3})

    def test_gaps_and_need_rollup(self):
        self.assertEqual(self.summary['by_need']['milk']['current_in_stock'], 1)
        self.assertEqual(self.summary['by_need']['milk']['historical'], 1)
        gaps = '\n'.join(self.summary['gaps'])
        self.assertIn('No current in-stock match at any queried branch: rice, eggs, coffee', gaps)
        self.assertIn('No price evidence from any queried source: rice, coffee, yogurt, tofu, soy sauce', gaps)
        self.assertIn('rejected by the app matching rules (review terms/rules): rice, eggs', gaps)
        self.assertIn('Lookup errors (rerun before drawing conclusions): tofu', gaps)
        self.assertIn('1 nearby store(s) have no product evidence', gaps)

    def test_markdown_lists_matrix_legend_and_samples(self):
        md = coverage.render_markdown(self.summary)
        self.assertIn('| milk | C (1) | H (1) 2025-05-01 |', md)
        self.assertIn('| soy sauce | - | - |', md)
        self.assertIn('`M` current match without a unit price', md)
        self.assertIn('| Synthetic Grocer | map_only | 2000 |', md)
        self.assertIn('**coffee**: Ground Coffee 1 gal - unknown', md)


class CollectionTests(unittest.TestCase):
    def setUp(self):
        api._CACHE.clear()

    def flags(self, kroger=False, geo=False):
        return {'KROGER_CLIENT_ID': kroger, 'KROGER_CLIENT_SECRET': kroger, 'GEOAPIFY_API_KEY': geo, 'LLM_API_KEY': False}

    def test_missing_credentials_skip_sources_without_requests(self):
        nearby = {'stores': [{**OPEN, 'price_count': 3, 'lat': 42.0, 'lon': -83.0},
                             {**MAP_ONLY, 'id': 'openprices:8', 'source': 'openprices', 'price_count': 0}],
                  'truncated': False}
        with patch.object(api, 'credential_status', return_value=self.flags()), \
             patch.object(api, 'kroger_get', side_effect=AssertionError('Kroger must not be called')), \
             patch.object(api, 'nearby_places', side_effect=AssertionError('Geoapify must not be called')), \
             patch.object(coverage, 'nearby_history', return_value=nearby), \
             patch.object(coverage, 'recommendation_records', return_value={'records': OPEN['records'], 'partial': True}):
            result = coverage.collect(['milk'], radius_m=5000, pause=0, now=NOW, log=silent)
        self.assertEqual(result['sources']['kroger']['status'], 'not_run')
        self.assertIn('KROGER_CLIENT_ID', result['sources']['kroger']['detail'])
        self.assertEqual(result['sources']['map']['status'], 'not_run')
        self.assertEqual([s['kind'] for s in result['stores']], ['historical', 'location_only'])
        self.assertTrue(result['stores'][0]['partial'])
        summary = coverage.summarize(result)
        self.assertEqual(summary['matrix']['openprices:7']['milk']['code'], 'H')
        self.assertTrue(any(g.startswith('kroger: not_run') for g in summary['gaps']))

    def test_kroger_uses_app_query_and_keeps_fulfillment_flags(self):
        raw = {'data': [{'productId': '111', 'description': 'Whole Milk', 'brand': 'Test', 'items': [
            {'itemId': '01', 'size': '1 gal', 'soldBy': 'unit', 'price': {'regular': 3.5},
             'inventory': {'stockLevel': 'HIGH'}, 'fulfillment': {'inStore': True, 'delivery': False}}]}]}
        def fake_get(path, params):
            if params['filter.term'] == 'eggs':
                raise api.ProviderError('Provider rate limit reached (HTTP 429).')
            return copy.deepcopy(raw)
        store = {k: KROGER[k] for k in ('id', 'external_id', 'name', 'address', 'lat', 'lon', 'source', 'distance_m')}
        with patch.object(api, 'credential_status', return_value=self.flags(kroger=True)), \
             patch.object(api, 'nearby_kroger', return_value=[store, {**store, 'id': 'kroger:2'}]), \
             patch.object(api, 'kroger_get', side_effect=fake_get) as get:
            result = coverage.collect(['milk', 'eggs'], max_kroger=1, sources=('kroger',), pause=0, log=silent)
        self.assertEqual(get.call_count, 2)                         # one branch x two needs
        params = get.call_args_list[0].args[1]
        self.assertEqual((params['filter.locationId'], params['filter.fulfillment']), ('1', 'ais'))
        lookups = result['stores'][0]['lookups']
        self.assertEqual(lookups['milk']['rows'][0]['fulfillment'], {'inStore': True, 'delivery': False})
        self.assertEqual(lookups['eggs']['status'], 'error')
        self.assertEqual(result['sources']['openprices']['status'], 'skipped')
        summary = coverage.summarize(result)
        self.assertEqual(summary['matrix']['kroger:1']['milk']['code'], 'C')
        self.assertEqual(summary['matrix']['kroger:1']['eggs']['code'], 'ERR')

    def test_map_lists_only_supermarkets_without_a_product_source(self):
        result = {'sources': {}, 'stores': [
            {'id': 'kroger:1', 'source': 'kroger', 'name': 'Kroger', 'address': '100 Test St, Ann Arbor',
             'lat': 42.0, 'lon': -83.0, 'kind': 'current', 'lookups': {}},
            {'id': 'openprices:7', 'source': 'openprices', 'name': 'Market', 'osm_id': 55, 'osm_type': 'node',
             'kind': 'historical', 'lookups': {}}]}
        places = [{'id': 'geoapify:k', 'name': 'Kroger', 'address': '100 Test St', 'lat': 42.0001, 'lon': -83.0},
                  {'id': 'geoapify:m', 'name': 'Market', 'address': '1 Elsewhere', 'lat': 42.01, 'lon': -83.0,
                   'osm_id': 55, 'osm_type': 'N'},
                  {'id': 'geoapify:g', 'name': 'Grocer', 'address': '9 Main St', 'lat': 42.02, 'lon': -83.0}]
        with patch.object(api, 'nearby_places', return_value=places):
            coverage._collect_map(result, 42.0, -83.0, 5000)
        self.assertEqual([s['id'] for s in result['stores'] if s['kind'] == 'map_only'], ['geoapify:g'])
        self.assertIn('3 supermarket POI(s); 1 without a product source', result['sources']['map']['detail'])


class ScriptTests(unittest.TestCase):
    def load(self):
        path = Path(__file__).resolve().parents[1] / 'scripts' / 'coverage_matrix.py'
        spec = importlib.util.spec_from_file_location('coverage_matrix', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_from_json_rerenders_offline_and_reports_partial_runs(self):
        script = self.load()
        partial = copy.deepcopy(COLLECTION)
        partial['sources']['kroger'] = {'status': 'not_run', 'detail': 'Configure KROGER_CLIENT_ID.'}
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'collection.json'
            source.write_text(json.dumps(partial))
            with patch.object(coverage, 'collect', side_effect=AssertionError('no network')), redirect_stdout(io.StringIO()) as out:
                status = script.main(['--from-json', str(source), '--out-dir', tmp])
            self.assertEqual(status, 1)
            self.assertIn('PARTIAL', out.getvalue())
            self.assertIn('| kroger | not_run |', (Path(tmp) / 'matrix.md').read_text())
            self.assertEqual(json.loads((Path(tmp) / 'summary.json').read_text())['kind'], 'Issue #2 coverage summary')

    def test_rejects_unknown_sources_and_unbounded_runs(self):
        script = self.load()
        for argv in (['--sources', 'walmart'], ['--max-kroger', '50'], ['--radius-m', '100']):
            with self.assertRaises(SystemExit), redirect_stdout(io.StringIO()), patch('sys.stderr', io.StringIO()):
                script.parse(argv)


if __name__ == '__main__':
    unittest.main()
