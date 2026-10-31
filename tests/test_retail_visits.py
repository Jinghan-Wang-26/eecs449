"""Synthetic retailer contracts and Jac policy; these are not live API evidence."""
import copy
import unittest
from unittest.mock import patch
import jaclang
from integrations import providers as api
from integrations.retail import quotes_for
from planning import visits
from planning.retail import apply_quotes, visit_rank
from tests.test_visits import context, TRAVEL, NOW, evidence

STORE = {'id':'kroger:1','external_id':'1','source':'kroger','product_access':True,
         'name':'Synthetic retailer','address':'100 Test St','lat':42.001,'lon':-83,'distance_m':100}
QUOTE = {'key':'kroger:111:01','external_id':'111','item_id':'01','store_id':'1','source':'kroger','mode':'live',
         'name':'Brown rice','brand':'Test','size_label':'1 kg','weight_kg':1,'price':3,'currency':'USD',
         'sold_by':'unit','availability':'IN_STOCK','in_store':True,'observed_at':NOW,'valid_until':'2030-01-01T10:30:00-05:00'}


def current_plan(rows=None, ctx=None, errors=None):
    ctx = ctx or context()
    with patch.object(visits, 'route', return_value=TRAVEL):
        plan = visits.candidate(STORE, evidence([]), ctx, NOW)
    return apply_quotes(plan, {'rows':{'rice':[copy.deepcopy(QUOTE)] if rows is None else rows},'errors':errors or {}}, ctx, NOW)


class RetailPolicyTests(unittest.TestCase):
    def test_branch_bound_current_prices_and_transparent_partial_cost(self):
        p=current_plan()
        self.assertEqual(p['current_subtotal'],6)
        self.assertEqual(p['current_available'],1)
        self.assertTrue(p['current_complete']);self.assertTrue(p['accept_allowed'])
        self.assertIsNone(p['reference_subtotal']);self.assertIsNone(p['estimated_total'])
        ctx=context();ctx['profile']['tax_rate']=.06
        self.assertEqual(current_plan(ctx=ctx)['estimated_total'],6.36)

    def test_matching_rejects_cross_branch_expired_wrong_specs_and_diet(self):
        for change in ({'store_id':'2'},{'valid_until':NOW},{'observed_at':'2031-01-01T00:00:00+00:00'},
                       {'in_store':False},{'name':'Rice crackers'},{'source':'openprices'}):
            self.assertIsNone(current_plan([dict(QUOTE,**change)])['items'][0]['quote'])
        for spec in ({'brand':'Other'},{'size':'2 kg'}):
            ctx=context();ctx['needs'][0].update(spec)
            self.assertEqual(current_plan(ctx=ctx)['matched'],0)
        ctx=context();ctx['profile']['dietary']=['vegan']
        self.assertEqual(current_plan(ctx=ctx)['matched'],0)

    def test_missing_price_stock_and_coverage_never_become_free_or_out(self):
        p=current_plan([dict(QUOTE,price=None,availability='UNKNOWN',weight_kg=None)])
        self.assertIsNone(p['current_subtotal']);self.assertEqual(p['current_available'],0)
        self.assertFalse(p['current_complete']);self.assertTrue(p['accept_allowed'])
        p=current_plan([]);self.assertIsNone(p['items'][0]['quote']);self.assertTrue(p['accept_allowed'])
        p=current_plan([],errors={'rice':'Rate limit reached'})
        self.assertFalse(p['accept_allowed'])

    def test_stockout_selects_available_alternative_and_no_alternative_blocks(self):
        p=current_plan([dict(QUOTE,availability='OUT')])
        self.assertFalse(p['accept_allowed'])
        alternate=dict(QUOTE,key='kroger:222:01',external_id='222',price=4)
        p=apply_quotes(current_plan(),{'rows':{'rice':[dict(QUOTE,availability='OUT'),alternate]},'errors':{}},context(),NOW)
        self.assertEqual(p['items'][0]['quote']['key'],alternate['key']);self.assertTrue(p['accept_allowed'])

    def test_budget_carry_and_ranking_do_not_reward_incomplete_cheaper_baskets(self):
        ctx=context();ctx['profile']['weekly_budget']=5
        self.assertFalse(current_plan(ctx=ctx)['accept_allowed'])
        ctx=context();ctx['profile']['carry_limit_kg']=1
        self.assertFalse(current_plan(ctx=ctx)['accept_allowed'])
        full=current_plan();cheap=current_plan([dict(QUOTE,price=.1,availability='UNKNOWN')])
        self.assertLess(visit_rank(full),visit_rank(cheap))
        self.assertLess(visit_rank(full),visit_rank(current_plan([dict(QUOTE,price=5)])))

    def test_recheck_keeps_same_item_when_available_and_reports_price_changes(self):
        plan=current_plan()
        with patch.object(visits,'quotes_for',return_value={'rows':{'rice':[dict(QUOTE,price=4)]},'errors':{}}) as fetch:
            refreshed=visits.refresh_visit(plan,context(),NOW)
        self.assertTrue(fetch.call_args.kwargs['refresh']);self.assertEqual(plan['current_subtotal'],6)
        self.assertEqual(refreshed['current_subtotal'],8);self.assertTrue(refreshed['quote_changes'])
        self.assertNotEqual(plan['quote_revision'],refreshed['quote_revision'])

    def test_route_expiring_during_recheck_prevents_acceptance(self):
        plan=current_plan();plan['route']['valid_until']='2030-01-01T10:00:01-05:00'
        with patch.object(visits,'quotes_for',return_value={'rows':{'rice':[QUOTE]},'errors':{}}),patch.object(visits.time,'monotonic',side_effect=[0,3]):
            result=visits.refresh_visit(plan,context(),NOW)
        self.assertFalse(result['accept_allowed'])

    def test_bus_schedule_retained_and_unknown_fare_not_zero(self):
        plan=current_plan();plan['route'].update(mode='BUS',cost=None,notice='Scheduled only; fare unknown',departure_at='2030-01-05T14:00:00-05:00')
        result=apply_quotes(plan,{'rows':{'rice':[QUOTE]},'errors':{}},context(),NOW)
        self.assertIsNone(result['estimated_total']);self.assertIsNone(result['transport_estimate'])
        self.assertEqual(result['route']['mode'],'BUS')
        self.assertIn('Scheduled only; fare unknown',result['warnings'])

    def test_recommendation_queries_supported_store_and_retains_real_route(self):
        with patch.object(visits,'nearby_with_history',return_value={'stores':[STORE],'notices':[]}),patch.object(visits,'route',return_value=TRAVEL),patch.object(visits,'quotes_for',return_value={'rows':{'rice':[QUOTE]},'errors':{}}):
            result=visits.recommend(context(),NOW)
        self.assertEqual(result['plans'][0]['current_subtotal'],6)
        self.assertEqual(result['plans'][0]['kind'],'CURRENT_STORE_VISIT')
        self.assertEqual(result['plans'][0]['route']['mode'],'WALK')


class RetailAdapterTests(unittest.TestCase):
    def setUp(self): api._CACHE.clear()

    def test_acceptance_rechecks_exact_product_and_search_without_cache(self):
        from tests.test_providers import RAW
        with patch.object(api,'required',return_value='synthetic'),patch.object(api,'kroger_get',return_value=RAW) as call:
            api.products('1','rice');api.products('1','rice');api.products('1','rice',refresh=True)
            self.assertEqual(call.call_count,2)
        with patch('integrations.retail.product_at',return_value=[dict(QUOTE,price=4)]) as exact,patch('integrations.retail.products',return_value=[QUOTE]) as search:
            result=quotes_for(STORE,context()['needs'],previous={'rice':QUOTE},refresh=True)
        self.assertEqual(result['rows']['rice'][0]['price'],4)
        exact.assert_called_once_with('1','111','rice');self.assertTrue(search.call_args.kwargs['refresh'])

    def test_failure_does_not_reuse_old_quote_and_list_is_bounded(self):
        with patch('integrations.retail.products',side_effect=api.ProviderError('Unavailable')) as fetch:
            result=quotes_for(STORE,[{'type':'item'+str(i),'qty':1} for i in range(9)])
        self.assertEqual(fetch.call_count,8);self.assertEqual(len(result['errors']),9)
        self.assertTrue(all(not rows for rows in result['rows'].values()))

    def test_weight_price_and_missing_selling_basis_never_multiply_by_packages(self):
        from tests.test_providers import RAW
        for basis in ('weight', '', None):
            raw=copy.deepcopy(RAW);raw['data'][0]['items'][0]['soldBy']=basis
            row=api.normalize_products(raw,'1','rice')[0]
            self.assertIsNone(row['price']);self.assertEqual(row['reported_price'],3.5)
        raw=copy.deepcopy(RAW);raw['data'][0]['items'][0]['inventory']='bad'
        with self.assertRaises(api.ProviderError):api.normalize_products(raw,'1','rice')

    def test_exact_product_is_branch_bound_and_rejects_wrong_product(self):
        from tests.test_providers import RAW
        with patch.object(api,'required',return_value='synthetic'),patch.object(api,'kroger_get',return_value={'data':RAW['data'][0]}) as get:
            self.assertEqual(api.product_at('1','111','rice')[0]['store_id'],'1')
            self.assertEqual(get.call_args.args,('products/111',{'filter.locationId':'1'}))
            with self.assertRaises(api.ProviderError):api.product_at('1','222','rice')

if __name__=='__main__':unittest.main()
