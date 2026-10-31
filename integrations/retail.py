"""Bounded retailer lookups. Matching and acceptance decisions live in Jac."""
from integrations.providers import products, product_at, ProviderError

MAX_NEEDS = 8


def quotes_for(store, needs, previous=None, refresh=False):
    rows, errors = {}, {}
    previous = previous or {}
    for index, need in enumerate(needs):
        category = need['type']
        rows[category] = []
        if index >= MAX_NEEDS:
            errors[category] = 'Lookup limit reached (8 needs per store). Split the shopping list.'
            continue
        try:
            selected = previous.get(category)
            # Recheck the exact selected product before discovering alternatives.
            exact = product_at(store['external_id'], selected['external_id'], category) if refresh and selected else []
            found = products(store['external_id'], category, refresh=refresh)
            by_key = {row['key']: row for row in found}
            # An exact response is authoritative for all variants of this product.
            if refresh and selected:
                by_key = {k: v for k, v in by_key.items() if v['external_id'] != selected['external_id']}
            by_key.update({row['key']: row for row in exact})
            rows[category] = list(by_key.values())
        except ProviderError as error:
            errors[category] = str(error)
    return {'rows': rows, 'errors': errors, 'limit': MAX_NEEDS}
