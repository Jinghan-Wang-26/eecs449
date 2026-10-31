"""Current retailer visits use uncached rechecks and explicit revision review."""
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.graph { Owns }
import from server.shopping { shopping_operation }
import from planning.visits { candidate }
import from tests.test_visits { TRAVEL, evidence }

glob WHEN: str = "2030-01-01T10:00:00-05:00";
import from tests.test_retail_visits { STORE, QUOTE }
import from models.events { ShoppingWorkspace }
import from models.graph { owned }
import from server.visits { visit_context, visit_action, visit_view }
import from planning.retail { apply_quotes }

def retail_user() -> any {
    p = UserProfile(data_mode='live', transport=['WALK'], weekly_budget=50, free_windows=['SAT 14:00-17:00']);
    p +>:Owns:+> InterestPool();
    p.location = {'id':'origin','address':'Synthetic address','lat':42,'lon':-83};
    shopping_operation(p,'save_interest',{'category':'rice','qty':2},WHEN);
    with patch('planning.visits.route',return_value=TRAVEL) { plan = candidate(STORE,evidence([]),visit_context(p,WHEN),WHEN); }
    state = owned(p, ShoppingWorkspace);
    state.visit_plans = [apply_quotes(plan, {'rows':{'rice':[dict(QUOTE)]},'errors':{}}, visit_context(p, WHEN), WHEN)];
    return p;
}

def accept_data(plan: dict) -> dict {
    return {'key':plan['key'], 'action':'accept', 'acknowledge_unknowns':True, 'quote_revision':plan['quote_revision']};
}

test "price change requires new revision and second explicit confirmation" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0]; old = accept_data(plan);
    row = dict(QUOTE); row['price'] = 4;
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[row]},'errors':{}}) {
        message = visit_action(p, old, WHEN);
        assert 'price changed' in message;
        assert plan['status'] == 'PROPOSED' and plan['current_subtotal'] == 8;
        assert not plan.get('accepted_at');
        failed = False;
        try { visit_action(p, old, WHEN); } except ValueError { failed = True; }
        assert failed;
        visit_action(p, accept_data(plan), WHEN);
    }
    assert plan['status'] == 'ACCEPTED' and plan.get('last_verified_at');
}

test "failed recheck clears stale prices and never accepts old inventory" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[]},'errors':{'rice':'Rate limit reached'}}) {
        visit_action(p, accept_data(plan), WHEN);
    }
    assert plan['status'] == 'NEEDS_REVIEW';
    assert plan['current_subtotal'] is None and plan['items'][0]['quote'] is None;
    assert not plan.get('accepted_at') and not plan['accept_allowed'];
}

test "stockout replaces product visibly and requires another acceptance" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    out = dict(QUOTE); out['availability'] = 'OUT';
    replacement = dict(QUOTE); replacement['key'] = 'kroger:222:02'; replacement['external_id'] = '222'; replacement['price'] = 4;
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[out,replacement]},'errors':{}}) {
        message = visit_action(p, accept_data(plan), WHEN);
    }
    assert 'selected product changed' in message;
    assert plan['items'][0]['quote']['key'] == 'kroger:222:02';
    assert plan['status'] == 'PROPOSED' and not plan.get('accepted_at');
}

test "explicit refresh can recover expired quotes while route is valid" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    later = '2030-01-01T10:40:00-05:00'; visit_view(p, later);
    assert plan['status'] == 'NEEDS_REVIEW' and plan['quotes_expired'];
    row = dict(QUOTE); row['observed_at'] = later; row['valid_until'] = '2030-01-01T11:10:00-05:00';
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[row]},'errors':{}}) {
        visit_action(p, {'key':plan['key'], 'action':'refresh'}, later);
    }
    assert plan['status'] == 'PROPOSED' and not plan['quotes_expired'];
    assert not plan.get('accepted_at');
}

test "unknown coverage requires explicit acknowledgment and fresh lookup" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[]},'errors':{}}) as lookup {
        visit_action(p, accept_data(plan), WHEN);
        assert plan['status'] == 'PROPOSED' and plan['current_subtotal'] is None;
        visit_action(p, accept_data(plan), WHEN);
        assert lookup.call_count == 2;
    }
    assert plan['status'] == 'ACCEPTED';
    assert plan['items'][0]['quote'] is None;
}


test "response view accounts for provider time instead of expiring newly fetched quotes" {
    p = retail_user(); plan = owned(p, ShoppingWorkspace).visit_plans[0];
    row = dict(QUOTE); row['observed_at'] = '2030-01-01T10:00:05-05:00';
    with patch('planning.visits.quotes_for', return_value={'rows':{'rice':[row]},'errors':{}}), patch('planning.visits.time.monotonic',side_effect=[0,5]) {
        visit_action(p,accept_data(plan),WHEN);
    }
    visit_view(p,WHEN);
    assert plan['status'] == 'ACCEPTED' and not plan['quotes_expired'];
    assert plan['accepted_at'] == plan['last_verified_at'];
}
