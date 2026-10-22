"""Reproduce a minimal public-address maps + historical-products request.

Run from repository root: python scripts/verify_live.py
No credential values, provider URL query keys or home addresses are printed.
Only the fixed public demo address is written to evidence output.
"""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from integrations import providers as maps
from integrations.openprices import nearby_history, price_records

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--env-dir',type=Path,help='Optional local .env directory; values never printed')
    parser.add_argument('--output',type=Path,default=Path('docs/samples/live-verification.json'))
    args=parser.parse_args()
    if args.env_dir:maps.ROOT=args.env_dir
    result={'kind':'actual provider verification','retrieved_at':maps.now_iso(),
            'public_demo_address':'150 E McKinley Avenue, Sunnyvale, CA 94086',
            'steps':{},'limitations':['Open Prices records are historical; current price and inventory unknown.']}
    failed=False
    # Independent shopping probe succeeds even when map credentials are pending.
    try:
        near=nearby_history(37.3739192,-122.0312241,1000)
        stores=near['stores']
        result['steps']['openprices_nearby']={'status':'ok','stores':stores}
        store=next((s for s in stores if s['external_id']=='4117'),None)
        if store is None:raise maps.ProviderError('Expected public demo store not found; choose a new documented sample.')
        records=price_records(store['external_id'])
        if not records['records']:raise maps.ProviderError('No historical prices returned at demo store.')
        result['steps']['openprices_products']={'status':'ok','total':records['total'],'records':records['records'][:3]}
    except ValueError as error:
        failed=True;result['steps']['openprices']={'status':'blocked','reason':str(error)}
    try:
        candidates=maps.geocode(result['public_demo_address'])
        if not candidates:raise maps.ProviderError('No candidate for public demonstration address.')
        chosen=candidates[0]
        result['steps']['geocoding']={'status':'ok','candidates':candidates}
        places=maps.nearby_places(chosen['lat'],chosen['lon'],1000)
        result['steps']['geoapify_places']={'status':'ok','stores':places}
        actual_near=nearby_history(chosen['lat'],chosen['lon'],1000)
        result['steps']['address_to_openprices']={'status':'ok','stores':actual_near['stores']}
        destination=next((s for s in actual_near['stores'] if s['external_id']!='4117'),None)
        if destination:
            result['steps']['routing']={'status':'ok','destination':destination['name'],
                'route':maps.route([chosen['lat'],chosen['lon']],[destination['lat'],destination['lon']],'WALK')}
    except ValueError as error:
        failed=True;result['steps']['maps']={'status':'blocked','reason':str(error)}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    for name,step in result['steps'].items():print(name+': '+step['status'])
    print('Evidence written to '+str(args.output))
    return 1 if failed else 0

if __name__=='__main__':sys.exit(main())
