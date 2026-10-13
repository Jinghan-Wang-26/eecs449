"""Deterministic catalog discovery, with explicit opt-in before planning."""

import from app_settings { get_settings, stamp, week_key }
import from models.profile { UserProfile }
import from models.catalog { Product }
import from models.interest { InterestItem, InterestKind, InterestStatus }
import from models.events { SyncState }
import from models.graph { Has, Wants, owned, catalog_of, items_of, pool_of, want }

def discover_products(p: UserProfile, now: str, settings: dict = {}) -> list {
    cfg = get_settings(settings);
    state = owned(p, SyncState);
    week = week_key(now, cfg);
    remaining = cfg["max_discovery_items_per_week"] - state.discovery_counts.get(week, 0);
    if remaining <= 0 {
        return [];
    }
    categories = [];
    excluded = [];
    for item in items_of(p) {
        if item.status == InterestStatus.ACTIVE and item.source == "USER" and item.kind != InterestKind.DISCOVER {
            categories.append(item.product_spec.get("type", ""));
        }
        for prod in [item ->:Wants:->] {
            link = [edge item ->:Wants:-> prod][0];
            if link.disliked or item.kind == InterestKind.DISCOVER or item.last_purchased_at != "" or link.confirmed {
                excluded.append(prod.key);
            }
        }
    }
    candidates = [];
    cat = catalog_of(p);
    for prod in [cat ->:Has:->][?:Product] {
        if prod.key in excluded or prod.category not in categories {
            continue;
        }
        # Unknown dietary compatibility does not satisfy an explicit requirement.
        if any([tag not in prod.tags for tag in p.dietary]) {
            continue;
        }
        preferred = p.brand_prefs.get(prod.category, "");
        score = 2.0 if preferred != "" and prod.brand == preferred else 1.0;
        candidates.append({"product": prod, "score": score});
    }
    candidates.sort(key=lambda row: dict : (-row["score"], row["product"].key));
    added = [];
    for row in candidates[:remaining] {
        prod = row["product"];
        reason = "Related to your stated interest in " + prod.category + ". Confirm before adding to your list.";
        item = InterestItem(
            product_spec={"type": prod.category, "product_key": prod.key, "qty": 1},
            kind=InterestKind.DISCOVER, source="INFERRED", confidence=0.5,
            interest_score=row["score"], discovered_at=stamp(now, cfg), discovery_reason=reason
        );
        pool_of(p) +>:Has:+> item;
        want(item, prod, substitute=True, confirmed=False);
        added.append(item);
    }
    state.discovery_counts = {**state.discovery_counts, week: state.discovery_counts.get(week, 0) + len(added)};
    return added;
}

def discovery_action(p: UserProfile, product_key: str, action: str) -> bool {
    if action not in ["accept", "dismiss"] {
        raise ValueError("Discovery action must be accept or dismiss");
    }
    for item in items_of(p) {
        if item.kind != InterestKind.DISCOVER or item.status != InterestStatus.ACTIVE or item.product_spec.get("product_key") != product_key {
            continue;
        }
        for link in [edge item ->:Wants:->] {
            link.confirmed = action == "accept";
            link.disliked = action == "dismiss";
        }
        if action == "accept" {
            # Merge with an existing need: planning keys are currently category-based.
            for need in items_of(p) {
                if need != item and need.kind != InterestKind.DISCOVER and need.status == InterestStatus.ACTIVE and need.product_spec.get("type") == item.product_spec["type"] {
                    if need.kind == InterestKind.WATCH { need.kind = InterestKind.NEED; }
                    for prod in [item ->:Wants:->] {
                        want(need, prod, substitute=True, confirmed=True);
                    }
                    item.status = InterestStatus.ARCHIVED;
                    return True;
                }
            }
            item.kind = InterestKind.NEED;
            item.source = "USER";
        } else {
            item.status = InterestStatus.ARCHIVED;
        }
        return True;
    }
    return False;
}
