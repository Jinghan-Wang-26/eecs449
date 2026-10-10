"""Mock provider: loads fictional stores, products, and offers from data/mock into a user's Catalog."""

import json;
import pathlib;
import from models.catalog { Catalog, Store, Product, Availability, Storage }
import from models.graph { upsert_store, upsert_product, upsert_offer, find_in }

glob MOCK_DIR: any = pathlib.Path(__file__).resolve().parent.parent / "data" / "mock";

"""Upsert everything in the file. Loading twice updates in place. Returns the number of offers."""
def load_mock(cat: Catalog, name: str = "catalog.json") -> int {
    data = json.loads((MOCK_DIR / name).read_text(encoding="utf-8"));
    for s in data["stores"] {
        upsert_store(cat, s["key"], {k: s[k] for k in s if k != "key"});
    }
    for p in data["products"] {
        fields = {k: p[k] for k in p if k != "key"};
        if "storage" in fields {
            fields["storage"] = Storage[fields["storage"]];
        }
        upsert_product(cat, p["key"], fields);
    }
    for o in data["offers"] {
        fields = {
            "price": o.get("price"),
            "member_price": o.get("member_price"),
            "member_program": o.get("member_program", ""),
            "availability": Availability[o.get("availability", "UNKNOWN")],
            "source": "mock",
            "mode": "mock",
            "observed_at": o.get("observed_at", data["observed_at"]),
            "valid_until": o.get("valid_until", data["valid_until"])
        };
        upsert_offer(cat, find_in(cat, Store, o["store"]), find_in(cat, Product, o["product"]), o["channel"], fields);
    }
    return len(data["offers"]);
}
