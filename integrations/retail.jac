"""Bounded retailer lookups. Matching and acceptance decisions live in Jac."""
import from integrations.providers { products, product_at, ProviderError }
import from app_settings { get_settings }
def quotes_for(
    store: any, needs: any, previous: any = None, refresh: any = False
) -> any {
    (rows, errors) = ({}, {});
    previous = previous or {};
    limit = get_settings()['max_active_needs'];
    for (index, need) in enumerate(needs) {
        category = need['type'];
        rows[category] = [];
        if (index >= limit) {
            errors[category] = f'Lookup limit reached ({limit} needs per store). Split the shopping list.';
            continue;
        }
        try {
            selected = previous.get(category);
            exact = (
                product_at(store['external_id'], selected['external_id'], category)
                    if (refresh and selected)
                    else []
            );
            term = ' '.join(
                part
                for part in (need.get('brand', ''), need.get('variant', ''), category)
                if part
            )[:80];
            found = products(store['external_id'], term, refresh=refresh);
            by_key = {row['key']: row for row in found};
            if (refresh and selected) {
                by_key = {
                    k: v
                    for (k, v) in by_key.items()
                    if (v['external_id'] != selected['external_id'])
                };
            }
            by_key.update({row['key']: row for row in exact});
            rows[category] = `list(by_key.values());
        } except ProviderError as error {
            errors[category] = str(error);
        }
    }
    return {'rows': rows, 'errors': errors, 'limit': limit};
}
