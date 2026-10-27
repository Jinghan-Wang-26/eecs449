"""Synthetic multi-store, scheduling and user-entered delivery regression tests."""
import copy
import unittest
from unittest.mock import patch
import jaclang
from planning import itineraries as trips
from planning.delivery import save_delivery_quote, delivery_issues
from planning.multistore import allocations, compose, choose_options
from planning.comparisons import extend_plans, refresh_comparison
from integrations.providers import ProviderError
from tests.test_retail_visits import current_plan, QUOTE, STORE
from tests.test_visits import context, NOW


def ctx():
    c=context();c['origin']['timezone']='America/New_York';c['profile']['tax_rate']=0;c['profile']['time_value_per_hour']=10
    c['needs']=[{'type':'rice','qty':1},{'type':'milk','qty':1}];c['delivery_quotes']=[]
    return c


def quote_data(categories=None):
    return dict(merchant='Synthetic merchant',source_url='https://www.kroger.com/',categories=categories or ['milk'],
                merchandise=4,delivery_fee=2,service_fee=1,other_fee=0,tax=0,tip=1,discount=0,minimum_order=0,
                address_confirmed=True,items_confirmed=True,fees_confirmed=True,
                window_start='2030-01-05T15:00:00-05:00',window_end='2030-01-05T16:00:00-05:00')


def stores():
    return [dict(STORE,opening_hours='24/7'),dict(STORE,id='kroger:2',external_id='2',name='Second synthetic store',lat=42.002,opening_hours='24/7')]


def item(category,store,price):
    q=dict(QUOTE,key='kroger:'+category,external_id='111' if category=='rice' else '222',name=category.title(),store_id=store['external_id'],price=price)
    return dict(category=category,qty=1,quote=q,store=store,fulfillment='IN_STORE',outcome='PENDING',evidence=None,reference_amount=None,current_amount=price,match_note='Synthetic',lookup_error='')


def parents():
    a,b=stores(); p=current_plan(); q=current_plan();p['store']=a;q['store']=b
    p['items']=[item('rice',a,2),item('milk',a,8)];q['items']=[item('rice',b,7),item('milk',b,3)]
    for plan in (p,q):
        plan['need_count']=2;plan['matched']=2;plan['current_available']=2;plan['current_subtotal']=10;plan['estimated_total']=10
    return [p,q]


def route(stops=None,context=None,delivery=None):
    stops=stops or stores();return trips.road_itinerary(stops,[{'minutes':m,'valid_until':'2030-01-01T11:00:00-05:00'} for m in ([4,7,9] if len(stops)==2 else [4,4])],'WALK',context or ctx(),NOW,delivery)


class DeliveryTests(unittest.TestCase):
    def test_fee_breakdown_preserves_zero_and_unknown(self):
        q=save_delivery_quote(quote_data(),ctx(),NOW)
        self.assertEqual(q['total'],8);self.assertFalse(q['api_verified']);self.assertEqual(delivery_issues(q,ctx(),NOW),[])
        q=save_delivery_quote(dict(quote_data(),service_fee=''),ctx(),NOW)
        self.assertIsNone(q['total']);self.assertIn('incomplete',' '.join(delivery_issues(q,ctx(),NOW)))

    def test_binding_rejects_address_quantity_and_spec_changes(self):
        q=save_delivery_quote(quote_data(),ctx(),NOW)
        for change in ('address','qty','brand','dietary'):
            c=ctx()
            if change=='address':c['origin']['lat']=43
            elif change=='dietary':c['profile']['dietary']=['vegan']
            else:c['needs'][1][change]=2 if change=='qty' else 'Other'
            self.assertIn('different address',' '.join(delivery_issues(q,c,NOW)))

    def test_expiry_and_receipt_window_and_minimum_order(self):
        q=save_delivery_quote(dict(quote_data(),minimum_order=10),ctx(),NOW)
        self.assertIn('minimum order',' '.join(delivery_issues(q,ctx(),NOW)))
        self.assertIn('expired',' '.join(delivery_issues(q,ctx(),'2030-01-01T10:31:00-05:00')))
        c=ctx();c['profile']['free_windows']=['SAT 16:00-17:00']
        self.assertIn('free time',' '.join(delivery_issues(q,c,NOW)))

    def test_invalid_urls_times_fees_and_false_attestations(self):
        for change in ({'source_url':'javascript:alert(1)'},{'source_url':'https://user:pass@example.com/'},
                       {'categories':['unknown']},{'categories':['milk','milk']},{'tip':'nan'}, {'delivery_fee':True},
                       {'window_start':'2030-01-05T15:00:00'},{'window_end':'2030-01-05T14:00:00-05:00'},
                       {'items_confirmed':False},{'discount':10}):
            with self.assertRaises(ValueError):save_delivery_quote(dict(quote_data(),**change),ctx(),NOW)


class ItineraryTests(unittest.TestCase):
    def test_two_stores_have_interstore_leg_two_shopping_stops_and_return(self):
        r=route()
        self.assertEqual(r['total_min'],60);self.assertEqual(r['shopping_min'],40)
        self.assertEqual([s['minutes'] for s in r['segments']],[4,7,9])
        self.assertEqual(r['return_at'],'2030-01-05T15:00:00-05:00')
        self.assertEqual(r['stops'][1]['shopping_at'],'2030-01-05T14:31:00-05:00')

    def test_store_hours_waiting_and_closed_second_store(self):
        ss=stores();ss[1]['opening_hours']='Sa 14:40-17:00'
        r=route(ss);self.assertEqual(r['total_min'],69);self.assertEqual(r['stops'][1]['wait_min'],9)
        ss[1]['opening_hours']='closed'
        with self.assertRaises(ProviderError):route(ss)

    def test_return_deadline_and_interstore_walk_limit(self):
        c=ctx();c['profile']['free_windows']=['SAT 14:00-14:59']
        with self.assertRaises(ProviderError):route(context=c)
        c=ctx();c['profile']['max_walk_min']=6
        with self.assertRaises(ProviderError):route(context=c)

    def test_mixed_trip_avoids_entire_delivery_window(self):
        q=save_delivery_quote(quote_data(),ctx(),NOW)
        r=route(delivery=q)
        self.assertLessEqual(r['return_at'],q['window_start'])
        q['window_start']='2030-01-05T14:30:00-05:00';q['window_end']='2030-01-05T16:30:00-05:00'
        with self.assertRaises(ProviderError):route(delivery=q)

    def test_three_scheduled_bus_segments_and_missing_return_block(self):
        from tests.test_transit import feed,link,trip,NOW as bus_now
        f=feed();f['trips']=[trip('out','1',[('A','14:10'),('B','14:20')]),trip('between','2',[('B','14:50'),('C','15:00')]),trip('back','3',[('C','15:30'),('A','15:40')])]
        c=ctx();c['profile']['transport']=['BUS'];c['profile']['max_transfers']=0;c['profile']['free_windows']=['TUE 14:00-17:00']
        def run():
            with patch.object(trips,'load_feed',return_value=f),patch.object(trips,'walking_links',side_effect=[({'A':link()},{'A':link()}),({'B':link()},{'B':link()}),({'C':link()},{'C':link()})]):
                return trips.bus_itinerary(stores(),c,bus_now)
        r=run();self.assertEqual(len(r['segments']),3);self.assertIsNone(r['cost']);self.assertEqual(r['shopping_min'],40)
        self.assertEqual([s['legs'][2]['route'] for s in r['segments']],['1','2','3'])
        f['trips']=f['trips'][:2]
        with self.assertRaises(ProviderError):run()


class ComparisonTests(unittest.TestCase):
    def test_cheapest_allocation_and_bounded_distinct_stores(self):
        choices=allocations(parents(),ctx())
        best=min(choices,key=lambda rows:sum(i['quote']['price'] for i in rows))
        self.assertEqual([i['store']['id'] for i in best],['kroger:1','kroger:2'])
        p=compose(best,None,stores(),route(),ctx(),NOW)
        self.assertEqual(p['estimated_total'],5);self.assertTrue(p['accept_allowed']);self.assertEqual(p['known_net_weight_kg'],2)

    def test_accumulated_weight_and_budget_block(self):
        c=ctx();c['profile']['carry_limit_kg']=1.5
        picked=[item('rice',stores()[0],2),item('milk',stores()[1],3)]
        p=compose(picked,None,stores(),route(),c,NOW)
        self.assertFalse(p['accept_allowed']);self.assertIn('Combined carried',' '.join(p['blockers']))
        c=ctx();c['profile']['weekly_budget']=4
        self.assertFalse(compose(picked,None,stores(),route(),c,NOW)['accept_allowed'])

    def test_delivery_fees_count_once_and_delivery_weight_is_not_carried(self):
        c=ctx();q=save_delivery_quote(quote_data(),c,NOW);c['delivery_quotes']=[q]
        r=route([stores()[0]],c,q)
        p=compose([item('rice',stores()[0],2)],q,[stores()[0]],r,c,NOW)
        self.assertEqual(p['estimated_total'],10);self.assertEqual(p['known_net_weight_kg'],1);self.assertEqual(p['active_min'],38)
        self.assertEqual(len(p['items']),2);self.assertEqual(p['items'][1]['fulfillment'],'DELIVERY')
        self.assertIsNone(p['items'][1]['quote']);self.assertTrue(p['accept_allowed'])

    def test_pure_delivery_no_routes_and_unknown_fees_cannot_win(self):
        c=ctx();q=save_delivery_quote(quote_data(['rice','milk']),c,NOW)
        good=compose([],q,[],None,c,NOW);self.assertEqual(good['estimated_total'],8);self.assertTrue(good['accept_allowed'])
        q['fees']['service_fee']=None;q['total']=None
        bad=compose([],q,[],None,c,NOW);self.assertFalse(bad['accept_allowed']);self.assertIsNone(bad['estimated_total'])
        self.assertIs(choose_options([bad,good])[0],good)

    def test_unknown_bus_fare_does_not_become_zero(self):
        r=route();r.update(mode='BUS',cost=None)
        p=compose([item('rice',stores()[0],2),item('milk',stores()[1],3)],None,stores(),r,ctx(),NOW)
        self.assertIsNone(p['estimated_total']);self.assertIsNone(p['transport_estimate'])

    def test_refresh_queries_each_assigned_branch_and_blocks_stockout(self):
        items=[item('rice',stores()[0],2),item('milk',stores()[1],3)]
        p=compose(items,None,stores(),route(),ctx(),NOW)
        def response(store,needs,**kwargs):
            self.assertTrue(kwargs['refresh']);self.assertEqual(len(needs),1)
            category=needs[0]['type'];q=dict(QUOTE,store_id=store['external_id'],name=category,price=4,availability='OUT' if category=='milk' else 'IN_STOCK')
            return {'rows':{category:[q]},'errors':{}}
        with patch('planning.comparisons.quotes_for',side_effect=response) as fetch:result=refresh_comparison(p,ctx(),NOW)
        self.assertEqual(fetch.call_count,2);self.assertFalse(result['accept_allowed']);self.assertTrue(result['quote_changes'])

    def test_end_to_end_bounded_search_keeps_representative_options(self):
        c=ctx();c['delivery_quotes']=[save_delivery_quote(quote_data(),c,NOW)]
        def schedules(stops,context,now,delivery):return ([(stops,route(stops,context,delivery))],[])
        with patch('planning.comparisons.itinerary_options',side_effect=schedules):options,_,count=extend_plans(parents(),c,NOW)
        self.assertIn('CURRENT_MULTI_VISIT',{p['kind'] for p in options});self.assertIn('MIXED_VISIT',{p['kind'] for p in options})
        self.assertLessEqual(len(options),7);self.assertGreater(count,len(options))

if __name__=='__main__':unittest.main()
