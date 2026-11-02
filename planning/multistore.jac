"""Bounded real-store allocation and user-entered checkout comparison rules."""
import copy;
import hashlib;
import json;
import uuid;
import from itertools { product }
import from app_settings { instant }
import from planning.retail { money, fresh_quote }
import from planning.delivery { delivery_issues }
import from planning.tax { estimate as estimate_tax }

def comparison_kind(plan: dict) -> bool { return plan.get('kind') in ['CURRENT_MULTI_VISIT','DELIVERY_VISIT','MIXED_VISIT']; }

def allocations(plans: list, context: dict, delivery: any = None) -> list {
    covered = delivery['categories'] if delivery is not None else [];
    needs = [n for n in context['needs'] if n['type'] not in covered]; choices = [];
    for need in needs {
        rows = [];
        for plan in plans {
            if plan.get('kind') != 'CURRENT_STORE_VISIT' { continue; }
            for item in plan['items'] {
                row = item.get('quote');
                if item['category'] != need['type'] or row is None or row['availability'] not in ['IN_STOCK','LOW'] or not money(row.get('price')) { continue; }
                value = copy.deepcopy(item); value['store'] = plan['store']; value['fulfillment'] = 'IN_STORE'; rows.append(value);
            }
        }
        if not rows { return []; }
        choices.append(rows);
    }
    results = [];
    for picks in product(*choices) {
        if len({item['store']['id'] for item in picks}) <= 2 { results.append(list(picks)); }
        if len(results) >= 4096 { break; }
    }
    return results;
}

def compose(items: list, delivery: any, stores: list, route: any, context: dict, now: str, route_errors: list = []) -> dict {
    items = copy.deepcopy(items); profile = context['profile']; blockers = []; warnings = [];
    subtotal = 0.0; mass = 0.0; weighed = 0; available = 0; priced = 0;
    for item in items {
        row = item.get('quote');
        if row and fresh_quote(row,now) and row.get('availability') in ['IN_STOCK','LOW'] { available += 1; }
        else { blockers.append(item['category'] + ': fresh available retailer evidence is required for this combined plan.'); }
        if row and money(row.get('price')) {
            item['current_amount'] = round(row['price']*item['qty'],2); subtotal += item['current_amount']; priced += 1;
        } else { item['current_amount'] = None; blockers.append(item['category'] + ': current retailer price is Unknown.'); }
        if row and money(row.get('weight_kg')) and row['weight_kg'] > 0 { mass += row['weight_kg']*item['qty']; weighed += 1; }
        if item.get('lookup_error') { blockers.append(item['category'] + ': ' + item['lookup_error']); }
    }
    retail_count = len(items); delivery_count = 0; delivery_total = 0;
    if delivery is not None {
        blockers.extend(delivery_issues(delivery,context,now)); delivery_count = len(delivery['items']); delivery_total = delivery['total'];
        for need in delivery['items'] {
            items.append({'category':need['type'],'qty':need['qty'],'outcome':'PENDING','evidence':None,'quote':None,
                'reference_amount':None,'current_amount':None,'fulfillment':'DELIVERY','delivery_quote_id':delivery['id'],
                'match_note':'Product choice, quantity and requirements confirmed by you at merchant checkout; not independently verified by API.',
                'merchant':delivery['merchant']});
        }
        warnings.append('Delivery is a user-entered merchant checkout quote, not an API quote or a placed order. Reconfirm the address, basket, all fees and delivery slot before accepting.');
    }
    if {i['category'] for i in items} != {n['type'] for n in context['needs']} or len(items)!=len(context['needs']) { blockers.append('This combined option does not cover every shopping need exactly once.'); }
    transport = None;
    if retail_count {
        if route is None { blockers.append('No verified continuous trip through every store and back home.'); }
        else {
            blockers.extend(route.get('violations',[])); transport = route.get('cost');
            if route['mode']=='CAR' and profile['transport_cost']>=0 { transport = profile['transport_cost']; warnings.append('Driving cost is your saved whole-trip estimate; check it for this itinerary.'); }
            if instant(route['valid_until']) <= instant(now) or instant(route['departure_at']) <= instant(now) { blockers.append('The route expired or the departure passed. Generate fresh recommendations.'); }
            if delivery is not None and not (instant(route['return_at'])<=instant(delivery['window_start']) or instant(route['departure_at'])>=instant(delivery['window_end'])) { blockers.append('The store trip overlaps the delivery window. You must be available at your address.'); }
            warnings.append(route.get('notice','Current route estimate; refresh before leaving.'));
        }
    } else { transport = 0; }
    subtotal = round(subtotal,2); tax_rate = profile.get('tax_rate',-1);
    tax = estimate_tax(items, [context['origin'].get('address','')], tax_rate);
    retail_total = round(subtotal+tax['tax']+transport,2) if priced==retail_count and (tax['tax'] is not None or retail_count==0) and money(transport) else None;
    total = round(retail_total + delivery_total,2) if retail_total is not None and delivery_total is not None else None;
    lower = subtotal + (transport if money(transport) else 0) + (delivery_total if money(delivery_total) else 0);
    if profile['weekly_budget']>0 and max(lower,total or 0)>profile['weekly_budget'] { blockers.append('Known costs exceed your saved budget.'); }
    if mass>profile['carry_limit_kg'] { blockers.append('Combined carried net weight exceeds your carrying limit.'); }
    if weighed<retail_count { warnings.append('Full carried weight is Unknown; available weights exclude packaging. Delivery items are not counted as carried.'); }
    if total is None { warnings.append('Full trip total is Unknown. Missing tax, transport or delivery fees are not treated as zero.'); }
    warnings.extend(['Stock levels do not guarantee requested quantities or future availability.','Selected products and package sizes may differ between options. Compare the item details; historical prices are never used in these totals.','Search is bounded to three retailer branches, at most two physical stops and one entered delivery quote.']);
    if route and route.get('hours_status')!='REGULAR_HOURS_FIT' { warnings.append('Some store opening hours are Unknown. Check all stores before travelling.'); }
    kind = 'MIXED_VISIT' if delivery is not None and retail_count else ('DELIVERY_VISIT' if delivery is not None else 'CURRENT_MULTI_VISIT');
    names = [s['name'] for s in stores] + ([delivery['merchant']+' delivery'] if delivery is not None else []);
    addresses = [s['address'] for s in stores];
    active = (route['total_min'] if route else 0) + (10 if delivery is not None else 0);
    value = {'key':str(uuid.uuid4()),'kind':kind,'status':'PROPOSED','created_at':now,
        'input_signature':hashlib.sha256(json.dumps(context,sort_keys=True,ensure_ascii=False).encode()).hexdigest(),
        'origin_label':context['origin'].get('address','Confirmed address'),'store':{'name':' + '.join(names),'address':' → '.join(addresses) or 'Delivery to your confirmed address'},
        'stops':copy.deepcopy(stores),'items':items,'delivery_quote':copy.deepcopy(delivery),'route':route,'route_notices':route_errors,'navigation_url':'',
        'need_count':len(context['needs']),'matched':len(items),'current_available':available,'covered_needs':available+delivery_count,
        'current_priced':priced+delivery_count if delivery_total is not None else priced,'current_complete':not blockers,
        'current_subtotal':round(subtotal+delivery['fees']['merchandise']-delivery['fees']['discount'],2) if delivery is not None and delivery['fees']['merchandise'] is not None and delivery['fees']['discount'] is not None else (subtotal if delivery is None else None),
        'retail_subtotal':subtotal,'delivery_total':delivery_total if delivery is not None else None,'estimated_total':total,'transport_estimate':transport,'tax_rate':tax_rate,'tax_estimate':tax['tax'],'tax_basis':tax['basis'],'tax_note':tax['note'],
        'active_min':active,'effective_total':round(total+active/60*profile.get('time_value_per_hour',0),2) if total is not None else None,
        'known_net_weight_kg':round(mass,2) if weighed or not retail_count else None,'weight_complete':weighed==retail_count,
        'reference_subtotal':None,'priced_needs':0,'checked_records':0,'quote_checked_at':now,
        'blockers':list(dict.fromkeys(blockers)),'warnings':warnings,'accept_allowed':not blockers,
        'explanation':'Compare the complete basket, continuous trip time, carrying limits and delivery fees. Accepting saves a plan; place any delivery order yourself on the merchant site.'};
    # Query timestamps change on every refresh; only material quote fields affect review.
    revision = [[i['category'],i.get('store',{}).get('id'),[ (i.get('quote') or {}).get(k) for k in ['key','price','availability','size_label','brand','name','weight_kg'] ],i.get('lookup_error')] for i in items];
    value['quote_revision'] = hashlib.sha256(json.dumps([revision,delivery.get('revision') if delivery is not None else None],sort_keys=True).encode()).hexdigest();
    return value;
}

def option_rank(plan: dict) -> tuple {
    complete = plan.get('current_complete',False);
    return (not plan['accept_allowed'], -plan.get('covered_needs',plan.get('current_available',plan['matched'])), not complete,
        plan.get('effective_total') if plan.get('effective_total') is not None else (plan.get('estimated_total') if plan.get('estimated_total') is not None else float('inf')),
        plan.get('active_min',plan['route']['total_min'] if plan['route'] else 100000), plan.get('current_subtotal') or 0);
}

def choose_options(plans: list) -> list {
    good = [p for p in plans if p['accept_allowed'] and p.get('current_complete')]; selected = [];
    priced = [p for p in good if p.get('estimated_total') is not None];
    labels = [];
    if priced { labels.append(('Lowest estimated total',min(priced,key=lambda p: p['estimated_total']))); }
    if good { labels.append(('Least active time',min(good,key=lambda p: p.get('active_min',p['route']['total_min'] if p['route'] else 100000)))); labels.append(('Balanced',min(good,key=option_rank))); }
    for (label,plan) in labels {
        plan.setdefault('comparison_labels',[]).append(label);
        if plan not in selected { selected.append(plan); }
    }
    for kind in ['CURRENT_MULTI_VISIT','DELIVERY_VISIT','MIXED_VISIT','CURRENT_STORE_VISIT','HISTORICAL_STORE_VISIT'] {
        group = [p for p in plans if p['kind']==kind];
        if group {
            plan = min(group,key=option_rank);
            if plan not in selected { selected.append(plan); }
        }
    }
    if not any([comparison_kind(p) for p in plans]) { return sorted(plans,key=option_rank)[:3]; }
    return selected[:7];
}
