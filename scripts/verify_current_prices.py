"""Opt-in authenticated retailer visit probe at a fixed public address; no LLM."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import jaclang
from app_settings import stamp
from integrations.providers import credential_status, geocode, ProviderError
from planning.visits import recommend, refresh_visit


def main():
    flags = credential_status()
    missing = [key for key in ('KROGER_CLIENT_ID','KROGER_CLIENT_SECRET','GEOAPIFY_API_KEY') if not flags[key]]
    if missing:
        print('BLOCKED: configure ' + ', '.join(missing) + ' in local .env. See docs/CURRENT_PRICES.md.')
        return 2
    output = Path('/tmp/cartcompass-current-prices-verification.json')
    result = {'kind':'Actual authenticated provider probe', 'checked_at':stamp(),
              'public_address':'Michigan Union, 530 South State Street, Ann Arbor, MI 48109',
              'passed':False, 'scope':'Retailer snapshots and route estimates; no stock reservation or checkout guarantee.'}
    try:
        origins=geocode(result['public_address'])
        if not origins:raise ProviderError('Public address did not resolve.')
        context={'origin':origins[0], 'radius_m':10000, 'needs':[{'type':'rice','qty':1}],
                 'profile':{'transport':['BUS','WALK'], 'max_walk_min':20,'max_transfers':1,
                            'free_windows':[day+' 08:00-20:00' for day in ('MON','TUE','WED','THU','FRI','SAT','SUN')],
                            'weekly_budget':100,'carry_limit_kg':6,'dietary':[],'tax_rate':.06,'transport_cost':-1}}
        found=recommend(context,stamp())
        result['notices']=found['notices']
        plans=[p for p in found['plans'] if p['kind']=='CURRENT_STORE_VISIT' and p['current_complete'] and p['accept_allowed']]
        if not plans:raise ProviderError('No complete, available retailer basket with a usable route was verified. Check scope, coverage and constraints.')
        plan=plans[0]; refreshed=refresh_visit(plan,context,stamp())
        result['proposed']=plan;result['rechecked']=refreshed
        result['passed']=refreshed['accept_allowed'] and refreshed['current_complete']
        result['review_required']=bool(refreshed['quote_changes'])
    except ValueError as error:
        result['reason']=str(error)
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(('PASS' if result['passed'] else 'BLOCKED') + ': evidence at ' + str(output))
    if result.get('reason'):print(result['reason'])
    return 0 if result['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
