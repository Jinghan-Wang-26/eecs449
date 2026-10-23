"""Opt-in real provider check at a fixed public address; no LLM calls or private addresses."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from integrations.providers import geocode, reverse_geocode, ProviderError
from planning.visits import recommend
from app_settings import stamp

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('/tmp/cartcompass-store-visits.json'))
    args=parser.parse_args()
    address='150 E McKinley Avenue, Sunnyvale, CA 94086'
    try:
        addresses=geocode(address)
        if not addresses: raise ProviderError('Public demo address not resolved.')
        origin=addresses[0]
        detected=reverse_geocode(origin['lat'],origin['lon'],20)
        if not detected: raise ProviderError('Reverse lookup returned no confirmation candidate.')
        context={'origin':origin,'radius_m':1000,'needs':[{'type':'rice','qty':1},{'type':'milk','qty':1}],
                 'profile':{'transport':['WALK'],'max_walk_min':45,'free_windows':[day+' 08:00-22:00' for day in ('MON','TUE','WED','THU','FRI','SAT','SUN')],
                            'weekly_budget':50,'carry_limit_kg':6,'dietary':[],'memberships':[],'transport_cost':-1}}
        result=recommend(context,stamp())
        evidence={'kind':'actual HTTP verification at fixed public address','public_address':address,'checked_at':stamp(),
                  'reverse_geocode_passed':bool(detected),'result':result}
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(evidence,indent=2)+'\n')
        for plan in result['plans']:
            print(json.dumps({'store':plan['store']['name'],'historical_matches':plan['matched'],'checked_records':plan['checked_records'],
                              'route_verified':bool(plan['route']),'accept_allowed':plan['accept_allowed']}),flush=True)
        passed=any(p['accept_allowed'] and p['matched'] for p in result['plans'])
        print('PASS' if passed else 'BLOCKED: no route-eligible option with matching evidence at the public example.')
        return 0 if passed else 1
    except ValueError as error:
        print(str(error));return 1

if __name__=='__main__':raise SystemExit(main())
