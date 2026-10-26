"""Offline contract tests: all response objects here are SYNTHETIC, not live evidence."""
import io
import json
import jaclang  # Enable direct imports of the migrated .jac modules.
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from integrations import providers as p
from integrations.validation import profile_patch, need_spec
from ai.intents import validate_intent, parse_request

RAW = {'data':[{'productId':'111','description':'Test Rice','brand':'Test','items':[
    {'itemId':'01','size':'2 lb','price':{'regular':3.5,'promo':2.5},'inventory':{'stockLevel':'LOW'},'fulfillment':{'inStore':True}},
    {'itemId':'02','size':'1 gal','fulfillment':{'inStore':True}},
]}]}

class ProviderTests(unittest.TestCase):
    def setUp(self):
        p._CACHE.clear()
        p._TOKEN.update(value='', expires=0, identity='')

    def test_product_variants_missing_values_and_provenance(self):
        a,b=p.normalize_products(RAW,'01400999','rice','2026-10-12T10:00:00+00:00')
        self.assertNotEqual(a['key'],b['key'])
        self.assertEqual(a['store_id'],'01400999')
        self.assertAlmostEqual(a['weight_kg'],.9072)
        self.assertEqual((a['price'],a['availability'],a['source'],a['mode']),(3.5,'LOW','kroger','live'))
        self.assertIsNone(b['price']); self.assertIsNone(b['weight_kg'])
        self.assertEqual(b['availability'],'UNKNOWN')
        self.assertEqual(a['valid_until'],'2026-10-12T10:30:00+00:00')

    def test_missing_or_invalid_price_never_zero(self):
        for bad in (float('nan'),-1,'3',True):
            data=json.loads(json.dumps(RAW));data['data'][0]['items'][0]['price']['regular']=bad
            self.assertIsNone(p.normalize_products(data,'1','rice')[0]['price'])

    def test_products_require_location_and_filter_query(self):
        with patch.object(p,'required',return_value='credential'),patch.object(p,'kroger_get',return_value=RAW) as get:
            with self.assertRaises(p.ProviderError):p.products('geoapify:store','rice')
            result=p.products('01400999','rice')
            self.assertEqual(get.call_args.args[1]['filter.locationId'],'01400999')
            result[0]['price']=999
            self.assertEqual(p.products('01400999','rice')[0]['price'],3.5)
            self.assertEqual(get.call_count,1)

    def test_oauth_cached_and_scope(self):
        with patch.object(p,'required',side_effect=lambda key:'secret' if key.endswith('SECRET') else 'id'),patch.object(p,'request_json',return_value={'access_token':'token','expires_in':1800}) as request:
            self.assertEqual(p.kroger_token(),'token');self.assertEqual(p.kroger_token(),'token')
            self.assertEqual(request.call_count,1)
            self.assertEqual(request.call_args.kwargs['body'],{'grant_type':'client_credentials','scope':'product.compact'})

    def test_address_order_and_two_way_routes(self):
        with patch.object(p,'required',return_value='key'),patch.object(p,'request_json',side_effect=[{'features':[{'properties':{'time':120,'distance':100}}]},{'features':[{'properties':{'time':180,'distance':140}}]}]) as request:
            result=p.route([42,-83],[43,-84],'WALK')
            self.assertEqual((result['min'],result['walk_min'],result['distance_m']),(5,3,240))
            self.assertEqual(request.call_args_list[0].kwargs['params']['waypoints'],'42.0,-83.0|43.0,-84.0')
            self.assertEqual(request.call_args_list[1].kwargs['params']['waypoints'],'43.0,-84.0|42.0,-83.0')
        with self.assertRaises(p.ProviderError):p.route([42,-83],[43,-84],'BUS')

    def test_geocode_and_places_coordinate_order(self):
        with patch.object(p,'required',return_value='key'),patch.object(p,'request_json',return_value={'results':[{'lat':42,'lon':-83,'place_id':'a','formatted':'Public address'}]}) as request:
            self.assertEqual(p.geocode('Public address')[0]['id'],'a')
            self.assertEqual(request.call_args.kwargs['params']['filter'],'countrycode:us')
        with patch.object(p,'required',return_value='key'),patch.object(p,'request_json',return_value={'features':[]}) as request:
            p.nearby_places(42,-83)
            self.assertEqual(request.call_args.kwargs['params']['filter'],'circle:-83.0,42.0,5000')

    def test_poi_name_alone_never_links_inventory(self):
        store={'id':'kroger:1','name':'Kroger','address':'100 Test St','lat':42,'lon':-83,'product_access':True}
        place={'id':'geo:2','name':'Kroger','address':'200 Test St','lat':42,'lon':-83,'product_access':False}
        self.assertEqual(len(p.merge_stores([place],[store])),2)
        place['address']='100 Test St'
        self.assertEqual(p.merge_stores([place],[store])[0]['map_id'],'geo:2')

    def test_partial_failure_preserves_location_only(self):
        with patch.object(p,'nearby_places',return_value=[{'id':'map','product_access':False}]),patch.object(p,'nearby_kroger',side_effect=p.ProviderError('missing credentials')):
            result=p.nearby(42,-83)
            self.assertFalse(result['stores'][0]['product_access']);self.assertEqual(len(result['notices']),1)

    def test_missing_credentials_and_error_redaction(self):
        with patch.object(p,'credentials',return_value={}):
            with self.assertRaisesRegex(p.ProviderError,'GEOAPIFY_API_KEY'):p.geocode('Address')
        error=HTTPError('https://test?apiKey=secret',401,'secret',{},io.BytesIO(b'secret'))
        with patch('urllib.request.urlopen',side_effect=error):
            with self.assertRaises(p.ProviderError) as ctx:p.request_json('https://test?apiKey=secret')
            self.assertNotIn('secret',str(ctx.exception)); self.assertIn('401',str(ctx.exception))
        with patch('urllib.request.urlopen',side_effect=URLError('secret')):
            with self.assertRaises(p.ProviderError) as ctx:p.request_json('https://test')
            self.assertNotIn('secret',str(ctx.exception))

    def test_bounded_retry(self):
        error=HTTPError('https://test',429,'rate limit',{},io.BytesIO())
        with patch('urllib.request.urlopen',side_effect=error) as req,patch('time.sleep'):
            with self.assertRaises(p.ProviderError):p.request_json('https://test')
            self.assertEqual(req.call_count,2)

    def test_input_and_model_validation(self):
        for data in ({'weekly_budget':'nan'},{'tax_rate':1},{'transport':['FLY']},{'free_windows':['SAT 25:00-26:00']},{'free_windows':['SAT 15:00-14:00']},{'password':'x'}):
            with self.assertRaises(ValueError):profile_patch(data)
        self.assertEqual(profile_patch({'free_windows':['SAT 14:00-17:00']}),{'free_windows':['SAT 14:00-17:00']})
        for qty in (0,-1,1.5,True):
            with self.assertRaises(ValueError):need_spec({'category':'milk','qty':qty})
        with self.assertRaises(ValueError):need_spec({'category':None})
        with self.assertRaises(ValueError):validate_intent({'intent':'purchase','price':0})
        with self.assertRaises(ValueError):validate_intent({'intent':'update','profile':{'location':{'lat':42}}})
        self.assertEqual(validate_intent({'intent':'update','needs':[{'category':'rice','qty':2}]})['needs'][0]['qty'],2)

    def test_llm_validated_and_missing_key(self):
        with patch('ai.intents.credentials',return_value={}):
            with self.assertRaisesRegex(p.ProviderError,'LLM_API_KEY'):parse_request('buy rice')
        with patch('ai.intents.credentials',return_value={'LLM_API_KEY':'secret'}),patch('ai.intents.request_json',return_value={'choices':[{'message':{'content':'{"intent":"update","needs":[{"category":"rice","qty":2}]}'}}]}) as req:
            self.assertEqual(parse_request('buy 2 rice')['needs'][0]['qty'],2)
            self.assertNotIn('tools',req.call_args.kwargs['body'])


class MatchingTests(unittest.TestCase):
    def test_match_help_preserves_prices_and_never_confirms(self):
        from ai.matching import rank_products
        rows=[{'key':'a','name':'Milk','brand':'Other','size_label':'1 gal','price':2},
              {'key':'b','name':'Milk','brand':'Preferred','size_label':'1 gal','price':4}]
        result=rank_products({'type':'milk','brand':'Preferred','size':'1 gal'},rows)
        self.assertEqual(result[0]['key'],'b');self.assertEqual(result[0]['price'],4)
        self.assertIn('Requested brand matches',result[0]['match_reason'])
        self.assertNotIn('confirmed',result[0]);self.assertNotIn('match_reason',rows[0])
        from ai.matching import satisfies_requested_spec
        self.assertFalse(satisfies_requested_spec({'brand':'Preferred'},'Other',''))
        self.assertFalse(satisfies_requested_spec({'size':'2 lb'},'','1 lb'))
        self.assertTrue(satisfies_requested_spec({'size':'1 gal'},'','1.0 gal'))

if __name__=='__main__':unittest.main()

class StoreHoursTests(unittest.TestCase):
    def setUp(self): p._CACHE.clear()

    def test_details_match_exact_osm_identity_even_when_place_ids_differ(self):
        store = {'place_id':'search-id', 'osm_id':123, 'osm_type':'NODE'}
        props = {'place_id':'details-id','opening_hours':'Mo-Su 08:00-22:00',
                 'timezone':{'name':'America/Los_Angeles'},
                 'datasource':{'raw':{'osm_id':123,'osm_type':'n'}}}
        with patch.object(p,'required',return_value='synthetic'), patch.object(p,'request_json',return_value={'features':[{'properties':props}]}) as req:
            result = p.store_details(store)
            self.assertEqual(result['opening_hours'],'Mo-Su 08:00-22:00')
            self.assertEqual(result['timezone'],'America/Los_Angeles')
            p.store_details(store)
            self.assertEqual(req.call_count,1)

    def test_different_store_or_osm_type_never_supplies_hours(self):
        for osm_id, kind in [(124,'n'),(123,'w'),(None,None)]:
            p._CACHE.clear()
            props = {'place_id':'different','name':'Same name','opening_hours':'24/7',
                     'datasource':{'raw':{'osm_id':osm_id,'osm_type':kind}}}
            with patch.object(p,'required',return_value='synthetic'), patch.object(p,'request_json',return_value={'features':[{'properties':props}]}):
                with self.assertRaises(p.ProviderError): p.store_details({'place_id':'search','osm_id':123,'osm_type':'n'})

    def test_geocoding_and_directional_minutes_preserve_timezone_and_round_up(self):
        with patch.object(p,'required',return_value='synthetic'), patch.object(p,'request_json',return_value={'results':[{'lat':37,'lon':-122,'timezone':{'name':'America/Los_Angeles'}}]}):
            self.assertEqual(p.geocode('Public address')[0]['timezone'],'America/Los_Angeles')
        with patch.object(p,'required',return_value='synthetic'), patch.object(p,'request_json',side_effect=[{'features':[{'properties':{'time':61,'distance':100}}]},{'features':[{'properties':{'time':121,'distance':150}}]}]):
            result=p.route([42,-83],[42.01,-83],'WALK')
            self.assertEqual((result['outbound_min'],result['return_min'],result['min']),(2,3,5))
