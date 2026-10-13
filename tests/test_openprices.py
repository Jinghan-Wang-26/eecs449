"""Synthetic Open Prices contract fixtures; real HTTP evidence is in docs/samples."""
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

if __name__=='__main__':unittest.main()
