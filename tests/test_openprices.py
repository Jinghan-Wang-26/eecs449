"""Synthetic Open Prices contract fixtures; real HTTP evidence is in docs/samples."""
import jaclang  # Enable imports of the native Jac application modules.
import unittest
from unittest.mock import patch
from integrations import openprices as op
from integrations import providers as p

class OpenPricesTests(unittest.TestCase):
    def setUp(self):p._CACHE.clear()
    def test_historical_record_never_becomes_current_offer(self):
        raw={'items':[{'id':12,'location_id':10,'proof_id':22,'product_code':'123',
            'product_name':'Rice','price':2.4,'price_is_discounted':True,'discount_type':'LOYALTY_PROGRAM',
            'currency':'USD','date':'2020-01-01','product':{'quantity':'2 lb','brands':'Test'}}]}
        row=op.normalize_records(raw,'10')[0]
        self.assertEqual(row['recorded_on'],'2020-01-01')
        self.assertEqual(row['availability'],'UNKNOWN');self.assertIsNone(row['current_price'])
        self.assertNotIn('valid_until',row);self.assertEqual(row['data_kind'],'historical')
        self.assertEqual(row['discount_type'],'LOYALTY_PROGRAM')
        self.assertEqual(row['proof_url'],'https://prices.openfoodfacts.org/proofs/22')
        self.assertEqual(op.normalize_records(raw,'11'),[])
        raw['items'][0]['proof_id']=None
        self.assertEqual(op.normalize_records(raw,'10'),[])
    def test_location_filter_and_pagination(self):
        with patch.object(op,'request_json',return_value={'items':[],'total':100,'pages':5,'page':2}) as request:
            data=op.price_records('4117',2)
            self.assertEqual(request.call_args.kwargs['params']['location_id'],'4117')
            self.assertEqual(request.call_args.kwargs['params']['page'],2)
            self.assertEqual(data['total'],100)
        with self.assertRaises(ValueError):op.price_records('kroger:1')
        with self.assertRaises(ValueError):op.price_records('1',True)
    def test_geo_radius_and_store_types(self):
        rows=[{'id':1,'type':'OSM','osm_tag_value':'supermarket','osm_lat':42,'osm_lon':-83,'price_count':4},
              {'id':2,'type':'OSM','osm_tag_value':'supermarket','osm_lat':43,'osm_lon':-83,'price_count':5},
              {'id':3,'type':'OSM','osm_tag_value':'restaurant','osm_lat':42,'osm_lon':-83,'price_count':1}]
        with patch.object(op,'request_json',return_value={'items':rows,'pages':1}):
            result=op.nearby_history(42,-83,1000)
            self.assertEqual([s['id'] for s in result['stores']],['openprices:1'])
    def test_no_coverage_is_explicit_and_no_kroger_without_credentials(self):
        with patch.object(p,'nearby_places',return_value=[]),patch.object(p,'credential_status',return_value={'KROGER_CLIENT_ID':False,'KROGER_CLIENT_SECRET':False}),patch.object(p,'nearby_kroger') as kroger,patch.object(op,'nearby_history',return_value={'stores':[],'truncated':False}):
            result=op.nearby_with_history(42,-83)
            self.assertEqual(result['stores'],[])
            self.assertIn('no contributed store records',result['notices'][0]);kroger.assert_not_called()
    def test_exact_osm_identity_only_deduplicates(self):
        mapstore={'id':'map','lat':42,'lon':-83,'osm_id':123,'osm_type':'n'}
        historical={'id':'op','lat':42,'lon':-83,'osm_id':123,'osm_type':'NODE'}
        with patch.object(p,'nearby_places',return_value=[mapstore]),patch.object(p,'credential_status',return_value={'KROGER_CLIENT_ID':False,'KROGER_CLIENT_SECRET':False}),patch.object(op,'nearby_history',return_value={'stores':[historical],'truncated':False}):
            self.assertEqual(len(op.nearby_with_history(42,-83)['stores']),1)
            historical['osm_id']=124
            self.assertEqual(len(op.nearby_with_history(42,-83)['stores']),2)
    def test_kroger_branches_replace_their_map_pois_and_failures_retry_then_warn(self):
        # Real formats from 2795 Windwood Drive, Ann Arbor (2026-11-16): the map lists the
        # Plymouth Nixon branch as plain "Kroger" 37 m from the API branch.
        poi={'id':'geo:k','name':'Kroger','address':'Kroger, 2641 Plymouth Road, Ann Arbor, MI 48105, United States of America','lat':42.3045371,'lon':-83.7089245,'product_access':False}
        other={'id':'geo:b','name':"Busch's Fresh Food Market",'address':"Busch's, 2240 South Main Street, Ann Arbor, MI 48103",'lat':42.30,'lon':-83.70,'product_access':False}
        branch={'id':'kroger:01800361','name':'Kroger - Plymouth Nixon','address':'2641 Plymouth Rd, Ann Arbor, MI, 48105','lat':42.304858,'lon':-83.70905,'source':'kroger','product_access':True}
        keys={'KROGER_CLIENT_ID':True,'KROGER_CLIENT_SECRET':True}
        with patch.object(p,'nearby_places',return_value=[poi,other]),patch.object(p,'credential_status',return_value=keys),patch.object(p,'nearby_kroger',return_value=[branch]),patch.object(op,'nearby_history',return_value={'stores':[],'truncated':False}):
            names=[s['name'] for s in op.nearby_with_history(42.317,-83.706)['stores']]
        self.assertEqual(sorted(names),["Busch's Fresh Food Market",'Kroger - Plymouth Nixon'])
        with patch.object(p,'nearby_places',return_value=[poi]),patch.object(p,'credential_status',return_value=keys),patch.object(p,'nearby_kroger',side_effect=[p.ProviderError('timed out'),[branch]]) as kroger,patch.object(op,'nearby_history',return_value={'stores':[],'truncated':False}):
            result=op.nearby_with_history(42.317,-83.706)
        self.assertEqual(kroger.call_count,2);self.assertEqual([s['name'] for s in result['stores']],['Kroger - Plymouth Nixon'])
        self.assertFalse(any(n.startswith('Kroger:') for n in result['notices']))
        with patch.object(p,'nearby_places',return_value=[poi]),patch.object(p,'credential_status',return_value=keys),patch.object(p,'nearby_kroger',side_effect=p.ProviderError('Provider unavailable or timed out.')),patch.object(op,'nearby_history',return_value={'stores':[],'truncated':False}):
            result=op.nearby_with_history(42.317,-83.706)
        self.assertEqual([s['name'] for s in result['stores']],['Kroger'])
        self.assertIn('Kroger: Provider unavailable or timed out.',result['notices'])

if __name__=='__main__':unittest.main()

class StoreMetadataMergeTests(unittest.TestCase):
    def test_only_exact_identity_transfers_map_hours_and_timezone(self):
        mapped={'id':'map','lat':42,'lon':-83,'osm_id':123,'osm_type':'n', 'place_id':'map-place', 'opening_hours':'24/7','timezone':'America/New_York'}
        historical={'id':'op','lat':42,'lon':-83,'osm_id':123,'osm_type':'NODE'}
        with patch.object(p,'nearby_places',return_value=[mapped]), patch.object(p,'credential_status',return_value={}), patch.object(op,'nearby_history',return_value={'stores':[historical],'truncated':False}):
            result=op.nearby_with_history(42,-83,include_kroger=False)['stores']
            self.assertEqual(len(result),1)
            self.assertEqual(result[0]['opening_hours'],'24/7')
            self.assertEqual(result[0]['timezone'],'America/New_York')
            self.assertNotIn('opening_hours',historical)
            historical['osm_id']=124
            result=op.nearby_with_history(42,-83,include_kroger=False)['stores']
            self.assertEqual(len(result),2)
            self.assertNotIn('opening_hours',result[0])
