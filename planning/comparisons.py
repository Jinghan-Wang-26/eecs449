"""Orchestrate retailer and routing adapters; allocation and constraints live in Jac."""
import copy
import math
import time
from datetime import timedelta
from urllib.parse import urlencode
from app_settings import instant
from integrations.itineraries import itinerary_options
from integrations.retail import quotes_for
from planning.delivery import delivery_issues
from planning.multistore import allocations, compose, choose_options, comparison_kind
from planning.retail import apply_quotes, quote_changes


def clock_after(now, started):
    return (instant(now) + timedelta(seconds=math.ceil(time.monotonic()-started))).isoformat()


def extend_plans(plans, context, now):
    started=time.monotonic(); proposals=list(plans); cache={}
    for plan in plans:
        plan['active_min']=plan['route']['total_min'] if plan['route'] else 100000
        total=plan.get('estimated_total')
        plan['effective_total']=round(total+plan['active_min']/60*context['profile'].get('time_value_per_hour',0),2) if total is not None else None
    for delivery in [None, *context.get('delivery_quotes',[])[:3]]:
        for items in allocations(plans,context,delivery):
            by_store={i['store']['id']:i['store'] for i in items}
            stores=[by_store[key] for key in sorted(by_store)]
            if delivery is None and len(stores)<2:continue
            key=(tuple(sorted(by_store)),delivery['id'] if delivery else '')
            if key not in cache:
                if not stores:cache[key]=([(stores,None)],[])
                else:cache[key]=itinerary_options(stores,context,clock_after(now,started),delivery)
            routes,errors=cache[key]
            for ordered,travel in routes or [(stores,None)]:
                plan=compose(items,delivery,ordered,copy.deepcopy(travel),context,clock_after(now,started),errors)
                if ordered:
                    origin=context['origin']; points=[f"{s['lat']},{s['lon']}" for s in ordered]
                    mode={'WALK':'walking','BIKE':'bicycling','CAR':'driving','BUS':'transit'}.get(travel['mode'] if travel else '', 'walking')
                    plan['navigation_url']='https://www.google.com/maps/dir/?'+urlencode({'api':1,'origin':f"{origin['lat']},{origin['lon']}",'destination':f"{origin['lat']},{origin['lon']}",'waypoints':'|'.join(points),'travelmode':mode})
                proposals.append(plan)
    ready=clock_after(now,started)
    for plan in proposals:
        route=plan['route']
        if route and (instant(route['valid_until'])<=instant(ready) or (route.get('departure_at') and instant(route['departure_at'])<=instant(ready))):
            plan['blockers'].append('Route expired or departure passed while comparing options. Refresh recommendations.')
            plan['accept_allowed']=False
    selected=choose_options(proposals)
    single=[p for p in plans if p.get('current_complete') and p['accept_allowed'] and p.get('estimated_total') is not None]
    for plan in selected:
        plan['compared_options']=len(proposals)
        if single and plan.get('estimated_total') is not None and comparison_kind(plan) and plan.get('delivery_quote') is None:
            baseline=min(single,key=lambda p:p['estimated_total'])
            identity=lambda p:{i['category']:(i.get('quote') or {}).get('key') for i in p['items']}
            plan['like_for_like']=identity(plan)==identity(baseline)
            plan['savings_vs_single']=round(baseline['estimated_total']-plan['estimated_total'],2) if plan['like_for_like'] else None
            plan['baseline_store']=baseline['store']['name']
    return selected,ready,len(proposals)


def refresh_comparison(plan,context,now):
    started=time.monotonic(); chosen=[]
    for store in plan['stops']:
        previous_items=[i for i in plan['items'] if i.get('store',{}).get('id')==store['id']]
        categories={i['category'] for i in previous_items}
        subset={**context,'needs':[n for n in context['needs'] if n['type'] in categories]}
        previous={i['category']:i.get('quote') for i in previous_items}
        lookup=quotes_for(store,subset['needs'],previous=previous,refresh=True)
        shell={**plan,'store':store,'items':previous_items,'blockers':[],'quote_blockers':[]}
        updated=apply_quotes(shell,lookup,subset,clock_after(now,started))
        chosen.extend([{**i,'store':store,'fulfillment':'IN_STORE'} for i in updated['items']])
    delivery=plan.get('delivery_quote')
    current=next((q for q in context.get('delivery_quotes',[]) if delivery and q['id']==delivery['id']),None)
    updated=compose(chosen,current or delivery,plan['stops'],plan['route'],context,clock_after(now,started),plan['route_notices'])
    if delivery is not None and (current is None or current['revision']!=delivery['revision']):
        updated['blockers'].append('The saved delivery quote was changed or removed. Generate new comparisons.')
        updated['accept_allowed']=False
    updated.update(key=plan['key'],created_at=plan['created_at'],navigation_url=plan['navigation_url'])
    updated['quote_changes']=quote_changes(plan,updated)
    return updated
