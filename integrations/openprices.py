"""Public Open Prices records. These are historical evidence, never current stock.

Data attribution: Open Prices / Open Food Facts, ODbL.
https://openfoodfacts.github.io/open-prices/guides/data/
"""
import math
import re
from .providers import request_json, cached, coords, distance_m, now_iso, ProviderError, weight_from_size

BASE = 'https://prices.openfoodfacts.org/api/v1'

def nearby_history(lat, lon, radius_m=5000):
    lat, lon = coords(lat, lon)
    radius_m = max(500, min(int(radius_m), 20000))
    def fetch():
        data = request_json(BASE + '/locations/nearby', params={
            'lat':lat, 'lon':lon, 'radius_km':radius_m/1000, 'size':100})
        stores=[]
        for row in data.get('items', []):
            if row.get('type') != 'OSM' or row.get('osm_tag_value') not in ('supermarket','grocery','convenience','department_store','wholesale'):
                continue
            try:
                slat,slon=coords(row['osm_lat'],row['osm_lon'])
                ident=int(row['id'])
            except (ValueError,TypeError,KeyError):
                continue
            dist=distance_m((lat,lon),(slat,slon))
            if dist>radius_m:continue
            stores.append({'id':f'openprices:{ident}','external_id':str(ident),
                'name':row.get('osm_name') or row.get('osm_brand') or 'Store',
                'address':row.get('osm_display_name') or '', 'lat':slat,'lon':slon,
                'source':'openprices','data_kind':'historical','product_access':row.get('price_count',0)>0,
                'price_count':row.get('price_count',0),'distance_m':round(dist),
                'osm_id':row.get('osm_id'),'osm_type':row.get('osm_type'),
                'source_url':f'https://prices.openfoodfacts.org/locations/{ident}',
                'hours':{}, 'observed_at':now_iso()})
        return {'stores':stores,'total_locations':data.get('total',len(stores)),
                'truncated':data.get('pages',1)>1}
    return cached('openprices:nearby',[lat,lon,radius_m],fetch,900)

def normalize_records(data, location_id):
    records=[]
    for row in data.get('items',[]):
        # Defend against an ignored location filter; never borrow another branch's data.
        if str(row.get('location_id')) != str(location_id):continue
        if row.get('duplicate_of') is not None:continue
        ident,proof=row.get('id'),row.get('proof_id')
        if not isinstance(ident,int) or not isinstance(proof,int):continue
        value=row.get('price')
        if type(value) not in (int,float) or not math.isfinite(value) or value<0:continue
        product=row.get('product') or {}
        size=product.get('quantity') or ''
        if not size and product.get('product_quantity') and product.get('product_quantity_unit'):
            size=f"{product['product_quantity']} {product['product_quantity_unit']}"
        records.append({'key':f'openprices:price:{ident}','record_id':ident,
            'name':row.get('product_name') or product.get('product_name') or row.get('category_tag') or 'Unnamed product',
            'barcode':row.get('product_code') or '', 'brand':product.get('brands') or '',
            'size_label':size,'weight_kg':weight_from_size(size),'price':value,
            'regular_price':row.get('price_without_discount'), 'discounted':bool(row.get('price_is_discounted')),
            'discount_type':row.get('discount_type') or '', 'price_per':row.get('price_per') or ('UNIT' if row.get('type') == 'PRODUCT' and row.get('product_code') else 'not specified'),
            'raw_price_per':row.get('price_per'), 'record_type':row.get('type') or '',
            'currency':row.get('currency') or 'Unknown', 'recorded_on':row.get('date') or 'Unknown',
            'retrieved_at':now_iso(), 'location_id':str(location_id), 'proof_id':proof,
            'source':'openprices', 'data_kind':'historical', 'availability':'UNKNOWN',
            'current_price':None, 'source_url':f'https://prices.openfoodfacts.org/prices/{ident}',
            'proof_url':f'https://prices.openfoodfacts.org/proofs/{proof}',
            'categories':product.get('categories_tags') or [],
            'labels':product.get('labels_tags') or []})
    return records

def price_records(location_id, page=1):
    if not isinstance(location_id,str) or not re.fullmatch(r'\d{1,20}',location_id):
        raise ProviderError('Select an Open Prices location returned by nearby search.')
    if type(page) is not int or not 1<=page<=100:
        raise ProviderError('Choose a records page between 1 and 100.')
    def fetch():
        data=request_json(BASE+'/prices',params={'location_id':location_id,'order_by':'-date,-id',
            'size':20,'page':page,'duplicate_of__isnull':'true'})
        return {'records':normalize_records(data,location_id),'page':data.get('page',page),
                'pages':data.get('pages',1),'total':data.get('total',0),'location_id':location_id}
    return cached('openprices:prices',[location_id,page],fetch,300)

def nearby_with_history(lat, lon, radius_m=5000, include_kroger=True):
    from .providers import nearby_places, nearby_kroger, credential_status
    notices=[]; maps=[]; stores=[]
    try:
        maps=nearby_places(lat,lon,radius_m)
    except ProviderError as error:
        notices.append(str(error))
    try:
        result=nearby_history(lat,lon,radius_m)
        stores=result['stores']
        if not stores:
            notices.append('Open Prices has no contributed store records within this radius. This does not mean there are no supermarkets nearby. Try another area; no product data is fabricated.')
        if result['truncated']:
            notices.append('Showing the first 100 nearby Open Prices locations; reduce the radius for a more complete local result.')
    except ProviderError as error:
        notices.append('Open Prices: '+str(error))
    # Deduplicate only with exact upstream OSM identity, never name similarity.
    def osm_identity(store):
        kind=str(store.get('osm_type')).upper()
        kind={'N':'NODE','W':'WAY','R':'RELATION'}.get(kind,kind)
        return str(store.get('osm_id')),kind
    known={osm_identity(s) for s in stores if s.get('osm_id') is not None}
    maps=[s for s in maps if osm_identity(s) not in known]
    flags=credential_status()
    if include_kroger and flags['KROGER_CLIENT_ID'] and flags['KROGER_CLIENT_SECRET']:
        try:stores+=nearby_kroger(lat,lon,radius_m)
        except ProviderError as error:notices.append('Kroger: '+str(error))
    notices.append('Open Prices contains historical contributed prices with incomplete coverage. Current prices and inventory remain unknown.')
    return {'stores':sorted(stores+maps,key=lambda s:distance_m((lat,lon),(s['lat'],s['lon']))),'notices':notices}


CATEGORY_TAGS = {"milk": "en:milks", "eggs": "en:eggs", "rice": "en:rices", "yogurt": "en:yogurts", "coffee": "en:coffees", "tofu": "en:tofu"}

def recommendation_records(location_id, terms):
    if not isinstance(location_id, str) or not re.fullmatch(r'\d{1,20}', location_id):
        raise ProviderError('Invalid Open Prices location.')
    tags = sorted({CATEGORY_TAGS[t] for t in terms if t in CATEGORY_TAGS})[:6]
    def fetch():
        rows, notices, partial = {}, [], False
        # Latest 40 records plus up to 20 category-filtered records per known need.
        queries = [{'page': 1}, {'page': 2}] + [{'product__categories_tags__contains': tag} for tag in tags]
        for query in queries:
            try:
                data = request_json(BASE+'/prices', params={'location_id': location_id, 'size': 20,
                    'order_by': '-date,-id', 'duplicate_of__isnull': 'true', **query})
                for row in normalize_records(data, location_id): rows[row['record_id']] = row
                partial = partial or data.get('pages', 1) > query.get('page', 1)
            except ProviderError:
                partial = True
                notices.append('Some historical record queries failed; available evidence is shown.')
        return {'records': list(rows.values()), 'checked': len(rows), 'partial': partial,
                'notice': ' '.join(sorted(set(notices)))}
    return cached('openprices:recommendations', [location_id, tags], fetch, 300)
