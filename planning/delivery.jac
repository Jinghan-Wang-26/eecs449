"""User-entered merchant checkout quotes: scoped, expiring and never API verified."""
import hashlib;
import json;
import uuid;
import from datetime { datetime, timedelta }
import from urllib.parse { urlsplit }
import from zoneinfo { ZoneInfo }
import from app_settings { instant, get_settings }
import from integrations.validation { number }
import from planning.schedule { WEEKDAYS, minute, wall_time }

glob FEE_FIELDS: list = ['merchandise', 'delivery_fee', 'service_fee', 'other_fee', 'tax', 'tip', 'discount', 'minimum_order'];

def basket_binding(context: dict, categories: list) -> str {
    needs = sorted([n for n in context['needs'] if n['type'] in categories], key=lambda n: n['type']);
    return hashlib.sha256(json.dumps({'origin':context['origin'], 'needs':needs, 'dietary':context['profile'].get('dietary',[])}, sort_keys=True).encode()).hexdigest();
}

def quote_window(value: any) -> str {
    if not isinstance(value, str) { raise ValueError('Enter a delivery time with a timezone offset.'); }
    try { parsed = datetime.fromisoformat(value.replace('Z','+00:00')); }
    except ValueError { raise ValueError('Enter valid delivery start and end times.'); }
    if parsed.tzinfo is None { raise ValueError('Delivery times must include a timezone offset.'); }
    return parsed.isoformat();
}

def save_delivery_quote(data: dict, context: dict, now: str) -> dict {
    if not context.get('origin') or not context.get('needs') { raise ValueError('Confirm an address and save shopping needs first.'); }
    merchant = data.get('merchant', ''); source = data.get('source_url', ''); categories = data.get('categories');
    if not isinstance(merchant, str) or not 2 <= len(merchant.strip()) <= 100 { raise ValueError('Enter a merchant name (2–100 characters).'); }
    if not isinstance(source, str) or len(source) > 500 { raise ValueError('Enter a public merchant URL.'); }
    url = urlsplit(source);
    if url.scheme != 'https' or not url.hostname or url.username or url.password { raise ValueError('Use a public HTTPS merchant URL without credentials.'); }
    if not isinstance(categories, list) or not categories or len(categories) > 6 or not all([isinstance(c, str) for c in categories]) or len(set(categories)) != len(categories) { raise ValueError('Select distinct shopping needs covered by this checkout quote.'); }
    if set(categories) - {n['type'] for n in context['needs']} { raise ValueError('Delivery quote contains an unknown shopping need.'); }
    if data.get('address_confirmed') is not True or data.get('items_confirmed') is not True { raise ValueError('Confirm that checkout serves this address and exactly covers the selected products, quantities and requirements.'); }
    values = {};
    for field in FEE_FIELDS {
        value = data.get(field);
        values[field] = None if value is None or value == '' else round(number(value, 0, 100000, field.replace('_',' ')), 2);
    }
    start = quote_window(data.get('window_start')); end = quote_window(data.get('window_end'));
    if not instant(now) < instant(start) < instant(end) <= instant(now) + timedelta(days=8) { raise ValueError('Choose a future delivery window within eight days.'); }
    if values['discount'] is not None and values['merchandise'] is not None and values['discount'] > values['merchandise'] { raise ValueError('The discount cannot exceed the merchandise subtotal.'); }
    total = None;
    if all([values[f] is not None for f in FEE_FIELDS]) {
        total = round(sum([values[f] for f in ['merchandise','delivery_fee','service_fee','other_fee','tax','tip']]) - values['discount'], 2);
    }
    return {'id':str(uuid.uuid4()), 'revision':str(uuid.uuid4()), 'source':'USER_CHECKOUT_QUOTE', 'api_verified':False,
        'merchant':merchant.strip(), 'source_url':source, 'categories':sorted(categories),
        'items':[dict(n) for n in context['needs'] if n['type'] in categories], 'binding':basket_binding(context,categories),
        'fees':values, 'total':total, 'fees_confirmed':data.get('fees_confirmed') is True,
        'address_label':context['origin'].get('address','Confirmed address'), 'entered_at':now,
        'valid_until':min(instant(now)+timedelta(minutes=30),instant(start)).isoformat(),
        'window_start':start, 'window_end':end};
}

def delivery_issues(quote: dict, context: dict, now: str) -> list {
    issues = [];
    if quote['binding'] != basket_binding(context,quote['categories']) { issues.append('The delivery quote belongs to a different address, product selection or quantity. Enter a new checkout quote.'); }
    if instant(quote['valid_until']) <= instant(now) or instant(quote['window_start']) <= instant(now) { issues.append('The delivery quote expired or its order deadline passed. Recheck merchant checkout and enter a fresh quote.'); }
    if quote['total'] is None or not quote['fees_confirmed'] { issues.append('Delivery fees are incomplete or unconfirmed. Unknown fees are not treated as zero.'); }
    fees = quote['fees'];
    if fees['minimum_order'] is not None and fees['merchandise'] is not None and fees['merchandise'] < fees['minimum_order'] { issues.append('The entered basket does not meet the merchant minimum order.'); }
    zone = ZoneInfo(context['origin'].get('timezone') or get_settings()['timezone']);
    start = instant(quote['window_start']).astimezone(zone); end = instant(quote['window_end']); fits = False;
    for window in context['profile']['free_windows'] {
        (weekday, interval) = window.split(); (a,b) = interval.split('-');
        if weekday != WEEKDAYS[start.weekday()] { continue; }
        begin = wall_time(start.date(),minute(a),zone); finish = wall_time(start.date(),minute(b),zone);
        if begin is not None and finish is not None and begin <= start and end <= finish { fits = True; }
    }
    if not fits { issues.append('Be available at your address throughout the delivery window; it does not fit your saved free time.'); }
    return issues;
}
