"""Sales-tax estimates for store baskets.

Built-in rules exist only for the states in STATE_RULES, found from the store's address.
Elsewhere the shopper's own rate from Preferences is used, or tax stays Unknown.
Estimates only: prepared food, deposits and local exceptions are not modelled.
"""
import re

# Michigan: 6% state sales tax and no local sales tax. Food for home consumption is
# exempt (MCL 205.54g); non-food goods and prepared food are taxed.
STATE_RULES = {
    'MI': {'name': 'Michigan', 'rate': 0.06, 'food_rate': 0.0,
           'note': 'Michigan: groceries exempt, household and personal items 6%'},
}

# Words in a shopping need that mark a non-food item. Words shared with foods
# (wraps, cups, bags, hot dog) are left out on purpose.
NON_FOOD = {
    'detergent', 'laundry', 'bleach', 'softener', 'cleaner', 'cleaning', 'wipes', 'sponge', 'sponges',
    'soap', 'shampoo', 'conditioner', 'toothpaste', 'toothbrush', 'floss', 'mouthwash', 'deodorant',
    'lotion', 'sunscreen', 'razor', 'razors', 'tissue', 'tissues', 'toilet', 'towel', 'towels',
    'napkins', 'foil', 'trash', 'garbage', 'batteries', 'bulb', 'bulbs',
    'vitamins', 'medicine', 'ibuprofen', 'acetaminophen', 'bandages', 'cosmetics', 'makeup',
    'litter', 'pet', 'charcoal', 'candles', 'utensils',
}
# Retailer aisle names (Kroger product categories) that hold non-food goods.
NON_FOOD_AISLES = ('cleaning', 'laundry', 'health', 'beauty', 'personal care', 'household',
                   'paper', 'pet', 'pharmacy', 'office')


def state_of(address):
    """Two-letter state before a ZIP code, e.g. 'Ann Arbor, MI 48105' or 'Ann Arbor, MI, 48105'."""
    found = re.findall(r'\b([A-Z]{2}),?\s+\d{5}(?:-\d{4})?\b', address or '')
    return found[-1] if found else ''


def taxable(category, aisles=()):
    """True for non-food goods. Anything without a non-food signal is treated as groceries."""
    if set(re.findall(r'[a-z]+', (category or '').lower())) & NON_FOOD:
        return True
    text = ' '.join(str(a) for a in aisles or ()).lower()
    return any(word in text for word in NON_FOOD_AISLES)


def estimate(items, fallback_addresses, user_rate):
    """Tax on priced store items.

    items: dicts with category, current_amount, and optionally quote.categories and store.address.
    fallback_addresses: tried in order when an item has no store address (store, then home).
    Returns {'tax', 'basis', 'note'}; tax is None when any priced item has no usable rule or rate.
    Each priced item also gets its own tax_amount (None when unknown) for the purchase record.
    basis is STATE_RULES, YOUR_RATE, MIXED, NONE (nothing priced) or UNKNOWN.
    """
    tax = 0.0; ruled = 0; rated = 0; notes = []; missing = set()
    for item in items:
        amount = item.get('current_amount')
        item['tax_amount'] = None
        if amount is None or item.get('fulfillment') == 'DELIVERY':
            continue
        places = [(item.get('store') or {}).get('address', '')] + list(fallback_addresses)
        state = next((s for s in map(state_of, places) if s), '')
        rule = STATE_RULES.get(state)
        if rule:
            aisles = (item.get('quote') or {}).get('categories', [])
            item['tax_amount'] = round(amount * (rule['rate'] if taxable(item.get('category'), aisles) else rule['food_rate']), 2)
            tax += item['tax_amount']
            ruled += 1
            if rule['note'] not in notes:
                notes.append(rule['note'])
        elif user_rate is not None and user_rate >= 0:
            item['tax_amount'] = round(amount * user_rate, 2)
            tax += item['tax_amount']
            rated += 1
        else:
            missing.add(state or 'unknown state')
    if missing:
        where = ', '.join(sorted(missing))
        return {'tax': None, 'basis': 'UNKNOWN',
                'note': f'No built-in tax rules for {where}. Add your sales-tax rate in Preferences.'}
    if rated:
        notes.append(f'your {round(user_rate * 100, 2)}% rate')
    basis = 'MIXED' if ruled and rated else ('STATE_RULES' if ruled else ('YOUR_RATE' if rated else 'NONE'))
    return {'tax': round(tax, 2), 'basis': basis, 'note': '; '.join(notes)}
