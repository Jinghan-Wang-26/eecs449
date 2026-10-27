"""Branch-bound quote matching, ranking and refresh rules; never infer inventory."""
import hashlib;
import json;
import math;
import from app_settings { instant }
import from ai.matching { tokens, satisfies_requested_spec }

def fresh_quote(row: dict, now: str) -> bool {
    try { return instant(row['observed_at']) <= instant(now) < instant(row['valid_until']); }
    except (KeyError, ValueError, TypeError) { return False; }
}

def money(value: any) -> bool {
    return type(value) in [int, float] and math.isfinite(value) and value >= 0;
}

def suitable(need: dict, row: dict, store: dict, dietary: list, now: str) -> bool {
    if row.get('source') != 'kroger' or row.get('mode') != 'live' or str(row.get('store_id')) != str(store['external_id']) { return False; }
    if not row.get('in_store') or not fresh_quote(row, now) { return False; }
    query = str(need['type']).lower(); query = {'egg': 'eggs', 'yoghurt': 'yogurt'}.get(query, query);
    name = tokens(row.get('name', ''));
    if not tokens(query).issubset(name) { return False; }
    exclusions = {'milk': ['chocolate','powder','soap','tea','coconut','almond','soy','soya','oat','oats','cashew','rice','condensed','evaporated'], 'rice': ['cake','cakes','cracker','crackers','noodles','cereal'], 'eggs': ['chocolate']};
    if name.intersection(exclusions.get(query, [])) { return False; }
    if not satisfies_requested_spec(need, row.get('brand', ''), row.get('size_label', '')) { return False; }
    # This adapter has no verified dietary certification. Do not assume suitability.
    if dietary { return False; }
    return True;
}

def quote_identity(plan: dict) -> str {
    values = [];
    for item in plan['items'] {
        row = item.get('quote') or {};
        values.append([item['category'], item['qty'], row.get('key'), row.get('price'), row.get('availability'), row.get('size_label'), row.get('brand'), row.get('name'), row.get('weight_kg'), item.get('lookup_error')]);
    }
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest();
}

def apply_quotes(plan: dict, lookup: dict, context: dict, now: str) -> dict {
    previous = {item['category']: item.get('quote') for item in plan['items']};
    items = []; subtotal = 0.0; priced = 0; available = 0; matched = 0; mass = 0.0; weighed = 0;
    old_blocks = plan.get('quote_blockers', []);
    plan['blockers'] = [b for b in plan['blockers'] if b not in old_blocks];
    blockers = [];
    for need in context['needs'] {
        category = need['type'];
        rows = [row for row in lookup['rows'].get(category, []) if suitable(need, row, plan['store'], context['profile']['dietary'], now)];
        old_key = (previous.get(category) or {}).get('key');
        # Keep a suitable, available selection stable on refresh. Otherwise prefer
        # available alternatives, then price; a stock-out is never a cheap option.
        rows.sort(key=lambda r: (r['availability'] not in ['IN_STOCK', 'LOW'], r['availability'] == 'OUT', r['key'] != old_key, not money(r.get('price')), r['price'] if money(r.get('price')) else float('inf'), r['key']));
        row = rows[0] if rows else None;
        error = lookup['errors'].get(category, '');
        item = {'category':category, 'qty':need['qty'], 'outcome':'PENDING', 'evidence':None, 'reference_amount':None, 'quote':row, 'current_amount':None, 'lookup_error':error,
            'match_note':'Review the selected product and package size before accepting.' if row else 'Unknown: no verified matching product in the checked results. This does not mean out of stock.'};
        if row {
            matched += 1;
            if row['availability'] in ['IN_STOCK','LOW'] { available += 1; }
            if row['availability'] == 'OUT' { blockers.append(category + ': selected product is out of stock; change the item or choose another store.'); }
            if money(row.get('price')) and row.get('currency') == 'USD' {
                item['current_amount'] = round(row['price'] * need['qty'], 2);
                subtotal += item['current_amount']; priced += 1;
            }
            if money(row.get('weight_kg')) and row['weight_kg'] > 0 { mass += row['weight_kg'] * need['qty']; weighed += 1; }
        }
        if error { blockers.append(category + ': retailer lookup unavailable. Refresh before accepting.'); }
        items.append(item);
    }
    subtotal = round(subtotal, 2);
    profile = context['profile']; route = plan['route'];
    transport = route.get('cost') if route else None;
    if route and route['mode'] == 'CAR' and profile['transport_cost'] >= 0 { transport = profile['transport_cost']; }
    tax_rate = profile.get('tax_rate', -1);
    total = round(subtotal * (1 + tax_rate) + transport, 2) if priced == len(items) and tax_rate >= 0 and money(transport) else None;
    if profile['weekly_budget'] > 0 and max(subtotal + (transport if money(transport) else 0), total or 0) > profile['weekly_budget'] {
        blockers.append('Known item costs plus available cost estimates exceed your saved budget. Adjust your list, budget or store.');
    }
    if mass > profile['carry_limit_kg'] { blockers.append('Known net product mass already exceeds your carrying limit.'); }
    warnings = ['Retailer lookup snapshots, not guaranteed checkout prices or exact inventory counts. LOW does not guarantee the requested quantity.',
        'Regular package prices only. Promotions, loyalty prices, substitutions and variable-weight totals require checking.',
        'Availability at a future visit is unknown. Refresh before departure; store hours may have holiday exceptions.',
        'Only up to 10 search results per need are checked. Product suitability requires your review.'];
    if priced < len(items) { warnings.append('Current subtotal is partial. Missing prices remain Unknown and are not treated as free.'); }
    if available < len(items) { warnings.append('Some items have unknown availability or are out of stock. This is not a guaranteed complete basket.'); }
    if weighed < len(items) { warnings.append('Full carrying weight is unknown; known net weights exclude packaging.'); }
    if total is None { warnings.append('Full trip cost is Unknown: tax, transport or some item prices are missing.'); }
    if route and route['mode'] == 'BUS' { warnings.append(route['notice']); }
    if plan['store'].get('details_notice') { warnings.append(plan['store']['details_notice']); }
    plan.update({'kind':'CURRENT_STORE_VISIT', 'items':items, 'matched':matched, 'current_available':available,
        'current_subtotal':subtotal if priced else None, 'current_priced':priced, 'current_complete':priced == len(items) and available == len(items),
        'estimated_total':total, 'transport_estimate':transport, 'tax_rate':tax_rate,
        'reference_subtotal':None, 'priced_needs':0, 'quote_checked_at':now,
        'known_net_weight_kg':round(mass, 2) if weighed else None, 'weight_complete':weighed == len(items),
        'quote_blockers':blockers, 'warnings':warnings});
    plan['blockers'].extend(blockers);
    plan['accept_allowed'] = not plan['blockers'];
    plan['quote_revision'] = quote_identity(plan);
    plan['explanation'] = f"{plan['store']['name']}: {available}/{len(items)} needs have matching products reported available. Ranked by travel eligibility, available coverage, complete-basket cost estimate when known, then travel time. Prices are retailer snapshots; historical options are labeled separately.";
    return plan;
}

def quote_changes(before: dict, after: dict) -> list {
    changes = [];
    previous = {item['category']: item.get('quote') or {} for item in before['items']};
    for item in after['items'] {
        category = item['category']; old = previous.get(category, {}); row = item.get('quote') or {};
        if old.get('key') != row.get('key') { changes.append(category + ': selected product changed or is now Unknown; review the updated item.'); }
        if old.get('price') != row.get('price') { changes.append(f"{category}: price changed from {old.get('price', 'Unknown')} to {row.get('price', 'Unknown')} USD per package."); }
        if old.get('availability') != row.get('availability') { changes.append(f"{category}: availability changed from {old.get('availability', 'UNKNOWN')} to {row.get('availability', 'UNKNOWN')}."); }
        if item.get('lookup_error') { changes.append(category + ': ' + item['lookup_error']); }
    }
    if not changes and before.get('quote_revision') != after.get('quote_revision') { changes.append('Product details changed. Review the updated selection.'); }
    return changes;
}

def visit_rank(plan: dict) -> tuple {
    travel = plan['route'];
    return (not plan['accept_allowed'], -plan.get('current_available', 0), -plan['matched'],
        not plan.get('current_complete', False),
        plan.get('estimated_total') if plan.get('estimated_total') is not None and plan.get('current_complete') else float('inf'),
        plan.get('current_subtotal') if plan.get('current_complete') else float('inf'),
        travel['total_min'] if travel else float('inf'), plan['store'].get('distance_m', 0));
}
