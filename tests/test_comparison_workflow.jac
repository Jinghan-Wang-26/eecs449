"""Persistent combined visits and delivery quote lifecycle without external writes."""
import uuid;
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.graph { Owns, owned, items_of }
import from models.events { ShoppingWorkspace }
import from server.shopping { shopping_operation }
import from server.workflows { workflow, start_new_plan }
import from server.visits { visit_context, visit_action, visit_view }
import from planning.multistore { compose }
import from tests.test_comparisons { quote_data, stores, item, route }

glob WHEN: str = '2030-01-01T10:00:00-05:00';

def comparison_user() -> any {
    p = UserProfile(data_mode='live',transport=['WALK'],weekly_budget=100,tax_rate=0,free_windows=['SAT 14:00-17:00']);
    p +>:Owns:+> InterestPool(); p.location = {'id':'origin','address':'Synthetic address','lat':42,'lon':-83,'timezone':'America/New_York'};
    shopping_operation(p,'save_interest',{'category':'rice','qty':1},WHEN);
    shopping_operation(p,'save_interest',{'category':'milk','qty':1},WHEN);
    return p;
}

def delivery_plan(p: any) -> dict {
    workflow(p,'save_delivery_quote',quote_data(['rice','milk']),WHEN);
    state = owned(p,ShoppingWorkspace);
    plan = compose([],state.delivery_quotes[0],[],None,visit_context(p,WHEN),WHEN);
    state.visit_plans = [plan]; return plan;
}

def confirmation(plan: dict) -> dict {
    return {'key':plan['key'],'action':'accept','acknowledge_unknowns':True,'quote_revision':plan['quote_revision'],'delivery_reconfirmed':True};
}

test "delivery requires explicit checkout reconfirmation and acceptance does not purchase" {
    p = comparison_user(); plan = delivery_plan(p); data = confirmation(plan); data['delivery_reconfirmed'] = False; failed = False;
    try { visit_action(p,data,WHEN); } except ValueError { failed = True; }
    assert failed and not plan.get('accepted_at');
    visit_action(p,confirmation(plan),WHEN);
    assert plan['status']=='ACCEPTED'; assert len([n for n in items_of(p) if n.plannable()])==2;
    visit_action(p,{'key':plan['key'],'action':'outcome','category':'rice','outcome':'PURCHASED'},WHEN);
    visit_action(p,{'key':plan['key'],'action':'outcome','category':'milk','outcome':'PURCHASED'},WHEN);
    assert plan['status']=='COMPLETED' and not [n for n in items_of(p) if n.plannable()];
}

test "expired manual quote is never renewed by refreshing retailer prices" {
    p = comparison_user(); plan = delivery_plan(p);
    visit_action(p,{'key':plan['key'],'action':'refresh'},'2030-01-01T10:31:00-05:00');
    assert plan['status']=='NEEDS_REVIEW' and not plan['accept_allowed'];
    assert plan['delivery_quote']['valid_until']=='2030-01-01T10:30:00-05:00';
}

test "quote update removes old proposal and new plan clears current checkout quotes" {
    p = comparison_user(); plan = delivery_plan(p); state = owned(p,ShoppingWorkspace);
    data = quote_data(['rice','milk']); data['replace_id'] = state.delivery_quotes[0]['id']; data['delivery_fee'] = 4;
    workflow(p,'save_delivery_quote',data,WHEN);
    assert plan['status']=='CANCELLED' and len(state.delivery_quotes)==1;
    assert state.delivery_quotes[0]['total']==10;
    start_new_plan(p,str(uuid.uuid4()),WHEN);
    assert state.delivery_quotes==[];
}

test "address or list edits cannot reuse a delivery plan" {
    p = comparison_user(); plan = delivery_plan(p);
    shopping_operation(p,'save_interest',{'category':'rice','qty':2},WHEN);
    failed = False;
    try { visit_action(p,confirmation(plan),WHEN); } except ValueError { failed = True; }
    assert failed and not plan.get('accepted_at');
}

test "two-store recheck keeps a review barrier for changed prices" {
    p = comparison_user(); context = visit_context(p,WHEN); ss = stores();
    items = [item('rice',ss[0],2),item('milk',ss[1],3)];
    plan = compose(items,None,ss,route(ss,context),context,WHEN);
    plan['comparison_labels'] = ['Lowest estimated total']; plan['savings_vs_single'] = 2;
    owned(p,ShoppingWorkspace).visit_plans = [plan];
    first = dict(items[0]['quote']); first['price'] = 4;
    second = dict(items[1]['quote']); second['price'] = 4;
    with patch('planning.comparisons.quotes_for',side_effect=[{'rows':{'rice':[first]},'errors':{}},{'rows':{'milk':[second]},'errors':{}}]) {
        message = visit_action(p,confirmation(plan),WHEN);
    }
    assert 'price changed' in message and plan['status']=='PROPOSED' and not plan.get('accepted_at');
    assert plan['estimated_total']==8;
    assert plan['comparison_labels']==[] and plan['savings_vs_single'] is None;
}
