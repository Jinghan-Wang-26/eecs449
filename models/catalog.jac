"""Catalog: Product, Store, and Offer. An Offer is one store selling one product through one channel."""

enum Availability { IN_STOCK, LOW, OUT, UNKNOWN }

enum Storage { AMBIENT, CHILLED, FROZEN }

"""Per-user cache of catalog data loaded by providers."""
node Catalog {}

node Product {
    has key: str,
        name: str = "",
        category: str = "",                # matches InterestItem.product_spec["type"]
        brand: str = "",
        size: float = 0.0,                 # package size in `unit`, for unit prices
        unit: str = "",                    # "gal", "lb", "oz", "ct", "fl oz"
        weight_kg: float = 0.0,
        storage: Storage = Storage.AMBIENT,
        tags: list[str] = [];              # dietary and flavor tags
}

node Store {
    has key: str,
        name: str = "",
        area: str = "",
        hours: dict = {},                  # {"SAT": "08:00-22:00"}
        channels: list[str] = ["IN_STORE"],
        routes: dict = {},                 # MVP fixed routes from home: {"BUS": {"min": 25, "cost": 1.5, "transfers": 0, "walk_min": 8}}
        delivery: dict = {};               # {"min_order": 10, "fee": 3.99, "free_over": 35, "service_pct": 0.05, "windows": [...]}
}

node Offer {
    has key: str,                          # "<store>:<product>:<channel>"
        channel: str = "IN_STORE",         # IN_STORE / PICKUP / DELIVERY
        price: float | None = None,        # None means unknown, never zero
        member_price: float | None = None,
        member_program: str = "",
        availability: Availability = Availability.UNKNOWN,
        source: str = "mock",
        mode: str = "mock",                # mock / live
        observed_at: str = "",
        valid_until: str = "";

    """Expired offers need a refresh before planning trusts them."""
    def is_fresh(now: str) -> bool {
        return self.valid_until == "" or now <= self.valid_until;
    }

    """Lowest price this user can actually pay; member prices need the membership."""
    def price_for(memberships: list[str]) -> float | None {
        if self.member_price is not None and self.member_program in memberships {
            return self.member_price;
        }
        return self.price;
    }
}
