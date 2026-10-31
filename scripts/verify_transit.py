"""Opt-in TheRide/Geoapify check at fixed public Ann Arbor locations. No LLM calls."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import jaclang
from app_settings import stamp
from integrations.providers import geocode, ProviderError
from planning.transit import bus_visit
from integrations.transit import load_feed


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('/tmp/cartcompass-transit-verification.json'))
    parser.add_argument('--scenario',choices=('standard','weekend'),default='standard',help='Weekend reproduces inactive nearby stops at the public Hubbard + Stone stop.')
    args=parser.parse_args()
    origin_address='Michigan Union, 530 South State Street, Ann Arbor, MI 48109'
    store_address='Kroger, 2641 Plymouth Road, Ann Arbor, MI 48105'
    try:
        if args.scenario=='weekend':
            stop=load_feed()['stops'].get('208')
            if not stop or stop['name']!='Hubbard + Stone':raise ProviderError('The public Hubbard + Stone verification stop changed; update this probe.')
            homes=[{'lat':stop['lat'],'lon':stop['lon'],'address':'TheRide public stop 208: Hubbard + Stone','timezone':'America/New_York'}]
        else:
            homes=geocode(origin_address)
        stores=geocode(store_address)
        if not homes or not stores:raise ProviderError('Public verification addresses could not be resolved.')
        origin=homes[0];destination=stores[0]
        store={'lat':destination['lat'],'lon':destination['lon'],'name':'Kroger on Plymouth Road',
               'address':destination['address'],'timezone':destination.get('timezone','America/New_York')}
        profile={'free_windows':[day+' 08:00-20:00' for day in ('MON','TUE','WED','THU','FRI','SAT','SUN')],
                 'max_walk_min':15,'max_transfers':1}
        if args.scenario=='weekend':profile['free_windows']=['SAT 14:00-17:00']
        result=bus_visit(origin,store,profile,stamp())
        evidence={'kind':'Actual HTTP timetable and walking verification at fixed public locations',
                  'checked_at':stamp(),'scenario':args.scenario,'origin':origin,'store':store,'profile':profile,'route':result,
                  'scope':'Scheduled service only; no live vehicle positions, delays, fares or inventory claims.'}
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2)+'\n')
        print(json.dumps({'passed':True,'departure':result['departure_at'],'return':result['return_at'],
            'round_trip_minutes_including_shopping':result['total_min'],'walking_minutes':result['total_walk_min'],
            'outbound_routes':[x['route'] for x in result['outbound']['legs'] if x['kind']=='BUS'],
            'return_routes':[x['route'] for x in result['returning']['legs'] if x['kind']=='BUS'],
            'feed_version':result['feed']['version'],'output':str(args.output)},indent=2))
        return 0
    except ValueError as error:
        print('BLOCKED: '+str(error));return 1

if __name__=='__main__':raise SystemExit(main())
