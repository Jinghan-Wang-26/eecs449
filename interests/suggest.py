"""Interest suggestions from the shopper's own purchases, for real-store mode.

USUAL: an item bought on at least two different days comes due after its usual gap.
SALE: a current Kroger promotion on something the shopper has bought or saved.
Both only suggest; nothing is added to the list until the shopper says yes.
"""
from app_settings import instant

MIN_GAP_DAYS = 2  # Two purchases closer than this are one shopping run, not a habit.
SALE_LIMIT = 4    # Retailer searches per check.


def purchase_days(entries, visits):
    """Category -> sorted purchase dates (YYYY-MM-DD) from the spending ledger and recorded visits."""
    days = {}
    for row in entries:
        if not row.get('voided') and row.get('category') and row.get('spent_at'):
            days.setdefault(row['category'].strip().lower(), set()).add(row['spent_at'][:10])
    for plan in visits:
        for item in plan.get('items', []):
            if (item.get('bought_qty') or 0) > 0 and item.get('recorded_at'):
                days.setdefault(item['category'].strip().lower(), set()).add(item['recorded_at'][:10])
    return {cat: sorted(values) for cat, values in days.items()}


def usual_due(days_by_category, now, listed):
    """Items whose usual gap since the last purchase has passed and that are not on the list."""
    today = instant(now).date()
    out = []
    for category, days in days_by_category.items():
        if category in listed or len(days) < 2:
            continue
        dates = [instant(day + 'T12:00').date() for day in days]
        gaps = [(b - a).days for a, b in zip(dates, dates[1:]) if (b - a).days >= MIN_GAP_DAYS]
        if not gaps:
            continue
        every = round(sum(gaps) / len(gaps))
        since = (today - dates[-1]).days
        if since >= every:
            out.append({'category': category, 'every': every, 'since': since, 'last': days[-1]})
    return sorted(out, key=lambda row: row['since'] - row['every'], reverse=True)


def sale_categories(days_by_category, saved, listed):
    """Bought categories, most recent first, then other saved interests; never ones on the list."""
    recent = sorted(days_by_category, key=lambda cat: days_by_category[cat][-1], reverse=True)
    ordered = list(dict.fromkeys(recent + list(saved)))
    return [cat for cat in ordered if cat and cat not in listed][:SALE_LIMIT]


def best_sale(rows, fits=None):
    """The biggest real promotion among available unit-priced products, or None."""
    best = None
    for row in rows:
        regular, promo = row.get('reported_price'), row.get('promotion')
        if type(regular) not in (int, float) or type(promo) not in (int, float):
            continue
        if not 0 < promo < regular or row.get('sold_by') != 'unit':
            continue
        if row.get('availability') not in ('IN_STOCK', 'LOW') or (fits and not fits(row)):
            continue
        if best is None or regular - promo > best['regular'] - best['promo']:
            best = {'row': row, 'regular': regular, 'promo': promo}
    return best


def search_term(spec):
    return ' '.join(part for part in (spec.get('brand', ''), spec.get('variant', ''), spec.get('type', '')) if part)[:80]
