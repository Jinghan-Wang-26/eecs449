"""Opt-in real two-store query and recheck at a public address; no orders or LLM."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import jaclang
from app_settings import stamp
from integrations.providers import credential_status, geocode, ProviderError
from planning.visits import recommend, refresh_visit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='/tmp/cartcompass-multistore-verification.json')
    args = parser.parse_args()
    flags = credential_status()
    missing = [k for k in ('KROGER_CLIENT_ID', 'KROGER_CLIENT_SECRET', 'GEOAPIFY_API_KEY') if not flags[k]]
    if missing:
        print('BLOCKED: configure ' + ', '.join(missing) + ' in local .env.')
        return 2
    result = {'kind': 'Actual authenticated provider probe', 'checked_at': stamp(), 'passed': False,
              'public_address': 'Michigan Union, 530 South State Street, Ann Arbor, MI 48109',
              'scope': 'Two Kroger branches and continuous road routes; no stock reservation or order. Delivery checkout amounts are not part of this live probe.',
              'test_inputs': {'tax_rate': .06, 'whole_trip_driving_cost': 5, 'time_value_per_hour': 10}}
    try:
        origins = geocode(result['public_address'])
        if not origins:
            raise ProviderError('Public address did not resolve.')
        context = {'origin': origins[0], 'radius_m': 10000,
                   'needs': [{'type': 'rice', 'qty': 1}, {'type': 'milk', 'qty': 1}], 'delivery_quotes': [],
                   'profile': {'transport': ['CAR'], 'max_walk_min': 20, 'max_transfers': 1,
                               'free_windows': [d+' 08:00-20:00' for d in ('MON','TUE','WED','THU','FRI','SAT','SUN')],
                               'weekly_budget': 100, 'carry_limit_kg': 10, 'dietary': [],
                               'tax_rate': .06, 'transport_cost': 5, 'time_value_per_hour': 10}}
        found = recommend(context, stamp())
        result['notices'] = found['notices']
        result['option_kinds'] = [p['kind'] for p in found['plans']]
        plans = [p for p in found['plans'] if p['kind'] == 'CURRENT_MULTI_VISIT' and p['accept_allowed']]
        if not plans:
            result['blockers'] = [p['blockers'] for p in found['plans'] if p['kind'] == 'CURRENT_MULTI_VISIT']
            raise ProviderError('No available two-store basket with a fitting continuous route. Check coverage and constraints.')
        plan = plans[0]
        refreshed = refresh_visit(plan, context, stamp())
        result['proposed'] = plan
        result['rechecked'] = refreshed
        result['review_required'] = bool(refreshed['quote_changes'])
        result['passed'] = refreshed['accept_allowed'] and refreshed['current_complete'] and len(refreshed['stops']) == 2 and len(refreshed['route']['segments']) == 3
    except ValueError as error:
        result['reason'] = str(error)
    output = Path(args.output)
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(('PASS' if result['passed'] else 'BLOCKED') + ': evidence at ' + str(output))
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
