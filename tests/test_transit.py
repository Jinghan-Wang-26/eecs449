"""Synthetic GTFS regression cases; tests make no network requests."""
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import jaclang
from planning import transit as t
from integrations import transit as adapter
from integrations.providers import ProviderError

NOW = '2026-10-27T12:00:00-04:00'
def epoch(value):
    return datetime.fromisoformat(value).timestamp()

def seconds(value):
    h,m = map(int,value.split(':')); return h * 3600 + m * 60

def trip(key, route, times, service='daily'):
    return {'trip_id':key, 'route_id':route, 'route_name':route, 'trip_headsign':'Synthetic destination', 'service_id':service,
            'stops':[{'stop':stop, 'arr':seconds(at), 'dep':seconds(at), 'seq':i+1, 'pickup':True, 'dropoff':True} for i,(stop,at) in enumerate(times)]}

def feed():
    return {'timezone':'America/New_York', 'start_date':'20261001', 'end_date':'20261130', 'version':'synthetic', 'fingerprint':'synthetic-only',
        'fetched_at':NOW, 'source_url':adapter.SOURCE_URL, 'feed_url':adapter.FEED_URL, 'skipped_trips':0,
        'calendar':[dict(service_id='daily', start_date='20261001', end_date='20261130', **{d:'1' for d in ('monday','tuesday','wednesday','thursday','friday','saturday','sunday')})],
        'exceptions':[], 'transfers':[],
        'stops':{k:{'id':k,'code':k,'name':'Stop '+k,'lat':42.28 + i*.001,'lon':-83.74} for i,k in enumerate('ABCD')},
        'trips':[trip('out','1',[('A','14:10'),('C','14:30')]),trip('back','2',[('C','15:00'),('A','15:20')])]}

def link(seconds=120):
    return {'seconds':seconds,'source':'Synthetic walking route','valid_until':'2026-10-27T13:00:00-04:00'}

def feed_bytes(value=None):
    f=value or feed(); files={
        'agency.txt':[{'agency_id':'x','agency_name':'Synthetic','agency_timezone':f['timezone']}],
        'feed_info.txt':[{'feed_start_date':f['start_date'],'feed_end_date':f['end_date'],'feed_version':f['version']}],
        'calendar.txt':f['calendar'], 'calendar_dates.txt':f['exceptions'],
        'stops.txt':[{'stop_id':s['id'],'stop_name':s['name'],'stop_lat':s['lat'],'stop_lon':s['lon']} for s in f['stops'].values()],
        'routes.txt':[{'route_id':r,'route_short_name':r,'route_long_name':'Synthetic','route_type':'3'} for r in sorted({x['route_id'] for x in f['trips']})],
        'trips.txt':[{k:v for k,v in x.items() if k in ('trip_id','route_id','trip_headsign','service_id')} for x in f['trips']],
        'stop_times.txt':[], 'transfers.txt':f['transfers']}
    for tr in f['trips']:
        for s in tr['stops']:
            def fmt(n):return f'{n//3600:02}:{n//60%60:02}:{n%60:02}'
            files['stop_times.txt'].append({'trip_id':tr['trip_id'],'stop_id':s['stop'],'stop_sequence':s['seq'],'arrival_time':fmt(s['arr']),'departure_time':fmt(s['dep']), 'pickup_type':'0' if s['pickup'] else '1','drop_off_type':'0' if s['dropoff'] else '1'})
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w') as z:
        for name, rows in files.items():
            if not rows:continue
            stream=io.StringIO();writer=csv.DictWriter(stream,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows);z.writestr(name,stream.getvalue())
    return buffer.getvalue()

class TimetableTests(unittest.TestCase):
    def search(self,f=None,transfers=1,links=None,forbidden=None,begin='2026-10-27T14:00:00-04:00',finish='2026-10-27T16:00:00-04:00'):
        f=f or feed();a,b=epoch(begin),epoch(finish)
        return t.journey(f,t.timed_trips(f,a,b),{'A':link()},{'C':link()},links or {},forbidden or set(),a,b,transfers,'Home','Store',lambda at:True)

    def test_calendar_exceptions_override_regular_service_and_add_special_day(self):
        f=feed();f['calendar'][0]['tuesday']='0'
        self.assertEqual(t.active_services(f,date(2026,10,27)),set())
        f['exceptions']=[{'service_id':'daily','date':'20261027','exception_type':'1'}]
        self.assertEqual(t.active_services(f,date(2026,10,27)),{'daily'})
        f['calendar'][0]['tuesday']='1';f['exceptions'][0]['exception_type']='2'
        self.assertEqual(t.active_services(f,date(2026,10,27)),set());self.assertIsNone(self.search(f))
        f['exceptions']=[{'service_id':'special','date':'20261027','exception_type':'1'}]
        self.assertIn('special',t.active_services(f,date(2026,10,27)))
        self.assertEqual(t.active_services(f,date(2027,1,1)),set())

    def test_direct_bus_has_explicit_walk_wait_and_fixed_boarding_time(self):
        result=self.search()
        self.assertEqual([x['kind'] for x in result['legs']],['WALK','WAIT','BUS','WALK'])
        self.assertEqual(result['departure'],epoch('2026-10-27T14:06:00-04:00'))
        self.assertEqual(result['arrival'],epoch('2026-10-27T14:32:00-04:00'))
        self.assertEqual(result['legs'][2]['trip_id'],'out');self.assertEqual(result['transfers'],0)
        self.assertEqual(result['wait_seconds'],120)

    def test_missed_departure_and_no_pickup_or_dropoff_are_not_routable(self):
        self.assertIsNone(self.search(begin='2026-10-27T14:08:00-04:00'))
        for index,field in ((0,'pickup'),(1,'dropoff')):
            f=feed();f['trips'][0]['stops'][index][field]=False
            self.assertIsNone(self.search(f))

    def test_transfers_respect_limit_buffer_minimum_and_forbidden_pairs(self):
        f=feed();f['trips']=[trip('one','1',[('A','14:10'),('B','14:20')]),trip('two','2',[('B','14:22'),('C','14:40')])]
        self.assertIsNone(self.search(f,transfers=0))
        result=self.search(f);self.assertEqual(result['transfers'],1)
        self.assertIsNone(self.search(f,forbidden={('B','B')}))
        self.assertIsNone(self.search(f,links={'B':{'B':dict(link(0),min_seconds=600)}}))
        f['trips'][1]['stops'][0]['dep']=seconds('14:21');f['trips'][1]['stops'][0]['arr']=seconds('14:21')
        self.assertIsNone(self.search(f))

    def test_transfer_walks_require_an_explicit_verified_connection(self):
        f=feed();f['trips']=[trip('one','1',[('A','14:10'),('B','14:20')]),trip('two','2',[('D','14:25'),('C','14:40')])]
        self.assertIsNone(self.search(f))
        result=self.search(f,links={'B':{'D':dict(link(180),min_seconds=10)}})
        self.assertEqual(result['transfers'],1)
        self.assertEqual(len([x for x in result['legs'] if x['kind']=='WALK']),3)
        self.assertIsNone(self.search(f,links={'B':{'D':dict(link(181),min_seconds=10)}}))

    def test_two_transfers_supported_but_not_invented_for_lower_limit(self):
        f=feed();f['trips']=[trip('a','1',[('A','14:10'),('B','14:20')]),trip('b','2',[('B','14:22'),('D','14:30')]),trip('c','3',[('D','14:32'),('C','14:40')])]
        self.assertIsNone(self.search(f,transfers=1));self.assertEqual(self.search(f,transfers=2)['transfers'],2)

    def test_previous_service_day_after_midnight_is_preserved(self):
        f=feed();f['trips']=[trip('night','N',[('A','25:10'),('C','25:30')])]
        f['exceptions']=[{'service_id':'daily','date':'20261028','exception_type':'2'}]
        result=self.search(f,begin='2026-10-28T01:00:00-04:00',finish='2026-10-28T02:00:00-04:00')
        self.assertEqual(result['legs'][2]['service_date'],'2026-10-27')
        self.assertEqual(result['arrival'],epoch('2026-10-28T01:32:00-04:00'))

    def test_dst_gtfs_elapsed_seconds_and_ambiguous_user_windows(self):
        z=ZoneInfo('America/New_York');d=date(2026,11,1)
        self.assertEqual(t.service_epoch(d,z),datetime(2026,11,1,12,tzinfo=z).timestamp()-43200)
        self.assertNotEqual(t.service_epoch(d,z),datetime(2026,11,1,0,tzinfo=z).timestamp())
        slots=t.availability(['SUN 01:00-02:00'],'2026-10-31T12:00:00-04:00','America/New_York')
        self.assertEqual(slots,[])

class TransitVisitTests(unittest.TestCase):
    def plan(self,f=None,windows=None,hours='Mo-Su 08:00-22:00',now=NOW,transfers=None):
        f=f or feed();origin={'lat':42.28,'lon':-83.74,'address':'Synthetic home','timezone':'America/New_York'}
        store={'lat':42.282,'lon':-83.74,'name':'Synthetic store','opening_hours':hours}
        profile={'free_windows':windows or ['TUE 14:00-16:00'],'max_walk_min':10,'max_transfers':1}
        with patch.object(t,'load_feed',return_value=f),patch.object(t,'walking_links',side_effect=[({'A':link()},{'A':link()}),({'C':link()},{'C':link()})]),patch.object(t,'transfer_links',return_value=(transfers or {},set())):
            return t.bus_visit(origin,store,profile,now)

    def test_round_trip_includes_return_wait_separate_shopping_and_unknown_fare(self):
        plan=self.plan();self.assertEqual(plan['mode'],'BUS');self.assertTrue(plan['scheduled_only'])
        self.assertEqual(plan['return_at'],'2026-10-27T15:22:00-04:00');self.assertEqual(plan['leave_store_at'],'2026-10-27T14:52:00-04:00')
        self.assertEqual(plan['store_wait_min'],4);self.assertEqual(plan['total_min'],76);self.assertEqual(plan['min'],56)
        self.assertEqual(plan['wait_min'],8);self.assertEqual(plan['total_walk_min'],8);self.assertIsNone(plan['cost'])
        self.assertEqual(plan['hours_status'],'REGULAR_HOURS_FIT')

    def test_last_return_bus_or_return_after_deadline_blocks_plan(self):
        f=feed();f['trips']=f['trips'][:1]
        with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(f)
        with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(windows=['TUE 14:00-15:10'])

    def test_closed_store_and_holiday_block_but_unknown_hours_are_explicit(self):
        with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(hours='Tu 08:00-14:40')
        f=feed();f['exceptions']=[{'service_id':'daily','date':'20261027','exception_type':'2'}]
        # Other dates within the eight-day horizon may still be offered.
        f['end_date']='20261027'
        with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(f)
        self.assertEqual(self.plan(hours='PH off; seasonal')['hours_status'],'UNKNOWN')

    def test_expired_feed_and_expired_walking_evidence_do_not_become_plans(self):
        f=feed();f['end_date']='20261026'
        with self.assertRaisesRegex(ProviderError,'does not cover'):self.plan(f)
        with self.assertRaisesRegex(ProviderError,'expired'):self.plan(now='2026-10-27T13:30:00-04:00')

    def test_actual_transfer_walk_can_invalidate_a_provisional_connection(self):
        f=feed();f['end_date']='20261027'
        f['trips']=[trip('one','1',[('A','14:10'),('B','14:20')]),trip('two','2',[('D','14:23'),('C','14:35')]),trip('back','3',[('C','15:10'),('A','15:30')])]
        def connections():
            return {'B':{'D':{'seconds':0,'min_seconds':0,'verified':False,'transfer_from':'B','transfer_to':'D','source':'provisional'}}}
        with patch.object(adapter,'route',return_value={'outbound_min':4,'valid_until':'2026-10-27T13:00:00-04:00'}) as request:
            with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(f,transfers=connections())
            self.assertEqual(request.call_count,1)
        with patch.object(adapter,'route',side_effect=ProviderError('unavailable')):
            with self.assertRaisesRegex(ProviderError,'round trip'):self.plan(f,transfers=connections())

    def test_slow_provider_completion_never_slides_a_scheduled_bus_departure(self):
        from planning import visits
        scheduled=self.plan();store={'id':'map:1','source':'geoapify','name':'Synthetic','address':'Test','lat':42.282,'lon':-83.74}
        context={'origin':{'id':'origin','lat':42.28,'lon':-83.74,'timezone':'America/New_York'},'radius_m':1000,
                 'needs':[{'type':'rice','qty':1}], 'profile':{'transport':['BUS'],'max_walk_min':10,'max_transfers':1,
                 'free_windows':['TUE 14:00-16:00'],'weekly_budget':50,'carry_limit_kg':6,'dietary':[],'transport_cost':-1}}
        with patch.object(visits,'nearby_with_history',return_value={'stores':[store],'notices':[]}),patch.object(visits,'store_details',return_value=store),patch.object(visits,'bus_visit',return_value=scheduled),patch.object(visits.time,'monotonic',side_effect=[0,10800]):
            result=visits.recommend(context,NOW)['plans'][0]
        self.assertEqual(result['route']['departure_at'],'2026-10-27T14:06:00-04:00')
        self.assertFalse(result['accept_allowed']);self.assertIn('Scheduled departure passed',result['blockers'][0])

class TransitAdapterTests(unittest.TestCase):
    def test_csv_parser_keeps_pickup_restrictions_and_detects_corrupt_data(self):
        f=feed();f['trips'][0]['stops'][0]['pickup']=False
        parsed=adapter.read_feed(feed_bytes(f),NOW)
        self.assertFalse(parsed['trips'][0]['stops'][0]['pickup'])
        self.assertEqual(len(parsed['fingerprint']),64)
        with self.assertRaises(ProviderError):adapter.read_feed(b'not a zip',NOW)

    def test_access_is_directional_and_never_replaced_with_straight_line_estimates(self):
        stops=feed()['stops'];response={'outbound_min':5,'return_min':12,'valid_until':'2026-10-27T13:00:00-04:00'}
        with patch.object(adapter,'route',return_value=response):
            with self.assertRaisesRegex(ProviderError,'walking connection'):adapter.walking_links([42.28,-83.74],stops,10)
            a,b=adapter.walking_links([42.28,-83.74],stops,15)
            self.assertEqual(a['A']['seconds'],300);self.assertEqual(b['A']['seconds'],720)
        with patch.object(adapter,'route') as call:
            with self.assertRaisesRegex(ProviderError,'Ann Arbor'):adapter.walking_links([37,-122],stops,15)
            call.assert_not_called()

    def test_forbidden_transfer_is_not_walked(self):
        f=feed();f['transfers']=[{'from_stop_id':'A','to_stop_id':'B','transfer_type':'3','min_seconds':0}]
        with patch.object(adapter,'route') as call:
            links,forbidden=adapter.transfer_links(f,10)
            self.assertNotIn('B',links.get('A',{}));self.assertEqual(forbidden,{('A','B')});call.assert_not_called()

    def test_daily_cache_reuse_and_failed_refresh_never_serves_stale_data(self):
        raw=feed_bytes();clock=epoch(NOW)
        with tempfile.TemporaryDirectory() as directory,patch.object(adapter,'CACHE_DIR',Path(directory)),patch.object(adapter,'_MEMORY',None),patch.object(adapter.time,'time',return_value=clock),patch.object(adapter,'_download',return_value=raw) as download:
            first=adapter.load_feed();self.assertEqual(adapter.load_feed()['fingerprint'],first['fingerprint']);self.assertEqual(download.call_count,1)
            adapter._MEMORY=None;self.assertEqual(adapter.load_feed()['fingerprint'],first['fingerprint']);self.assertEqual(download.call_count,1)
            with patch.object(adapter.time,'time',return_value=clock+adapter.MAX_AGE+1),patch.object(adapter,'_download',side_effect=ProviderError('offline')):
                with self.assertRaisesRegex(ProviderError,'offline'):adapter.load_feed()


class VerifiedTransferTests(unittest.TestCase):
    def test_provisional_connection_is_replaced_or_removed_before_publication(self):
        f=feed();links,_=adapter.transfer_links(f,10)
        edge=links['A']['B'];self.assertFalse(edge['verified'])
        journey={'legs':[t.walking_leg('A','B',0,edge)]}
        with patch.object(adapter,'route',return_value={'outbound_min':4,'valid_until':'2026-10-27T13:00:00-04:00'}):
            self.assertTrue(adapter.verify_transfer_paths([journey],links,f,10))
            self.assertTrue(links['A']['B']['verified']);self.assertEqual(links['A']['B']['seconds'],240)
        links,_=adapter.transfer_links(f,10);journey={'legs':[t.walking_leg('A','B',0,links['A']['B'])]}
        with patch.object(adapter,'route',side_effect=ProviderError('no pedestrian route')):
            self.assertTrue(adapter.verify_transfer_paths([journey],links,f,10))
            self.assertNotIn('B',links['A'])

class ServiceAwareAccessTests(unittest.TestCase):
    def test_inactive_nearest_stops_do_not_hide_a_weekend_round_trip(self):
        f=feed()
        for i in range(8):
            key='inactive'+str(i)
            f['stops'][key]={'id':key,'name':'Weekday-only stop','code':key,'lat':42.28+i*.00001,'lon':-83.74}
        f['stops']['A']['lat']=42.284;f['stops']['C']['lat']=42.286
        # These additional trips overlap the clock time but do not run Saturday.
        f['calendar'].append(dict(f['calendar'][0],service_id='weekday',saturday='0',sunday='0'))
        f['trips'].append(trip('weekday','W',[('inactive0','14:10'),('inactive1','14:30')],service='weekday'))
        requested=[]
        def access(point,stops,maximum):
            requested.append(set(stops))
            return adapter.walking_links(point,stops,maximum)
        origin={'lat':42.28,'lon':-83.74,'timezone':'America/New_York'}
        store={'lat':42.286,'lon':-83.74,'name':'Synthetic store'}
        profile={'free_windows':['SAT 14:00-17:00'],'max_walk_min':15,'max_transfers':1}
        with patch.object(t,'load_feed',return_value=f),patch.object(t,'walking_links',side_effect=access),patch.object(t,'transfer_links',return_value=({},set())),patch.object(adapter,'route',return_value={'outbound_min':2,'return_min':2,'valid_until':'2026-10-27T13:00:00-04:00'}):
            result=t.bus_visit(origin,store,profile,NOW)
        self.assertTrue(result['scheduled_only'])
        self.assertEqual(requested,[{'A','C'},{'A','C'}])
        self.assertTrue(result['departure_at'].startswith('2026-10-31'))
        self.assertLessEqual(result['walk_min'],15)

    def test_selection_filters_service_date_time_and_pickup_dropoff(self):
        f=feed();f['trips']=[trip('early','1',[('A','10:00'),('B','10:20')]),trip('current','2',[('C','14:10'),('D','14:30')])]
        a,b=epoch('2026-10-27T14:00:00-04:00'),epoch('2026-10-27T16:00:00-04:00')
        values=t.timed_trips(f,a,b)
        self.assertEqual(set(t.service_stops(f,values,a,b)),{'C','D'})
        values[0]['stops'][0].update(pickup=False,dropoff=False)
        self.assertEqual(set(t.service_stops(f,values,a,b)),{'D'})
        f['exceptions']=[{'service_id':'daily','date':'20261027','exception_type':'2'}]
        self.assertEqual(t.service_stops(f,t.timed_trips(f,a,b),a,b),{})

    def test_missing_return_and_no_service_have_distinct_diagnostics(self):
        checker=TransitVisitTests();f=feed();f['trips']=f['trips'][:1]
        with self.assertRaisesRegex(ProviderError,'outbound bus was found.*no verified return'):checker.plan(f)
        f=feed();f['trips']=[]
        with self.assertRaisesRegex(ProviderError,'No scheduled service overlaps'):checker.plan(f)

    def test_different_free_time_windows_use_different_active_stops(self):
        f=feed();f['trips']=[trip('earlier','1',[('A','09:10'),('B','09:30')]),trip('later','2',[('C','14:10'),('D','14:30')])]
        results=[]
        for start,end in [('09:00','10:00'),('14:00','15:00')]:
            a,b=epoch('2026-10-27T'+start+':00-04:00'),epoch('2026-10-27T'+end+':00-04:00')
            results.append(set(t.service_stops(f,t.timed_trips(f,a,b),a,b)))
        self.assertEqual(results,[{'A','B'},{'C','D'}])

    def test_multistore_checks_only_stops_served_in_its_window(self):
        from planning import itineraries
        from tests.test_comparisons import stores, ctx
        f=feed();f['trips']=[trip('out','1',[('A','14:10'),('B','14:20')]),trip('between','2',[('B','14:50'),('C','15:00')]),trip('back','3',[('C','15:30'),('A','15:40')])]
        context=ctx();context['profile']['free_windows']=['TUE 14:00-17:00'];context['profile']['max_transfers']=0
        connections=iter([({'A':link()},{'A':link()}),({'B':link()},{'B':link()}),({'C':link()},{'C':link()})])
        def access(point,stops,maximum):
            self.assertEqual(set(stops),{'A','B','C'})
            return next(connections)
        with patch.object(itineraries,'load_feed',return_value=f),patch.object(itineraries,'walking_links',side_effect=access):
            result=itineraries.bus_itinerary(stores(),context,NOW)
        self.assertEqual(len(result['segments']),3)
