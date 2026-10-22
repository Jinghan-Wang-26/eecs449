"""Explain product-match candidates using evidence, without confirming substitutions.

LLM-extracted brand/size constraints can rank returned retailer products, but a
text similarity score is not proof of equivalence, dietary suitability or stock.
"""
import re

def tokens(value):
    return set(re.findall(r'[a-z0-9]+',str(value).lower()))

def rank_products(spec, rows):
    query=tokens(spec.get('type',''))
    brand=str(spec.get('brand','')).strip().lower()
    size=str(spec.get('size','')).strip().lower()
    ranked=[]
    for row in rows:
        row=dict(row)
        overlap=len(query & tokens(row.get('name','')))
        score=overlap
        reasons=['Search-term words appear in the product name.' if overlap else 'Returned by retailer search; category equivalence is unverified.']
        if brand:
            match=brand==str(row.get('brand','')).strip().lower()
            score+=3 if match else -3
            reasons.append('Requested brand matches.' if match else 'Requested brand does not match; review this substitution.')
        if size:
            match=size==str(row.get('size_label','')).strip().lower()
            score+=2 if match else -2
            reasons.append('Requested package size matches.' if match else 'Requested size is not an exact text match; check package quantity.')
        row['match_reason']=' '.join(reasons)+' Confirm the product explicitly before planning.'
        row['match_score']=score
        ranked.append(row)
    return sorted(ranked,key=lambda row:(-row['match_score'],row.get('key','')))

def satisfies_requested_spec(spec, brand, size_label):
    """Conservative exact-spec fallback; explicit confirmed substitutions are separate."""
    requested_brand=str(spec.get('brand','')).strip().casefold()
    if requested_brand and requested_brand!=str(brand).strip().casefold():return False
    def size_key(value):
        value=re.sub(r'(?<=\d)\.0+(?=\s|$)', '', str(value).strip().lower())
        return re.sub(r'\s+', '', value)
    requested_size=size_key(spec.get('size',''))
    return not requested_size or requested_size==size_key(size_label)
