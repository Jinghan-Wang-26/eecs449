"""Synthetic timetable journeys integrated with visit acceptance and profile changes."""
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.events { ShoppingWorkspace }
import from models.graph { Owns, owned }
import from server.shopping { shopping_operation }
import from server.visits { visit_context, visit_action, visit_view }
import from planning.visits { candidate }
import from ai.conversation { plan_summary }
import from tests.test_transit { feed, link, NOW }

def transit_user() -> UserProfile {
    p = UserProfile(data_mode="live", transport=["BUS"], max_transfers=1, free_windows=["TUE 14:00-16:00"]);
    p +>:Owns:+> InterestPool();
    p.location = {"id":"synthetic","lat":42.28,"lon":-83.74,"address":"Synthetic home","timezone":"America/New_York"};
    shopping_operation(p,"save_interest",{"category":"rice","qty":1},NOW);
    store = {"id":"synthetic","external_id":"", "name":"Synthetic store","address":"Synthetic destination", "lat":42.282,"lon":-83.74,"opening_hours":"Mo-Su 08:00-22:00"};
    with patch("planning.transit.load_feed", return_value=feed()),
         patch("planning.transit.walking_links", side_effect=[({'A':link()},{'A':link()}),({'C':link()},{'C':link()})]),
         patch("planning.transit.transfer_links", return_value=({},set())) {
        plan = candidate(store, {"records":[],"checked":0,"partial":True,"notice":""}, visit_context(p,NOW),NOW);
    }
    owned(p,ShoppingWorkspace).visit_plans = [plan];
    return p;
}

test "scheduled bus visit is accepted explicitly and summarized without current fare claims" {
    p = transit_user(); plan = owned(p,ShoppingWorkspace).visit_plans[0];
    assert plan['accept_allowed'] and plan['route']['mode'] == 'BUS';
    assert plan['route']['cost'] is None and plan['reference_subtotal'] is None;
    assert 'travelmode=transit' in plan['navigation_url'];
    text = plan_summary({'visit_plans':[plan]},'en');
    assert 'scheduled bus 1' in text and 'scheduled bus 2' in text;
    assert 'live delays/cancellations and fares are unknown' in text;
    visit_action(p,{'key':plan['key'],'action':'accept','acknowledge_unknowns':True},NOW);
    assert plan['status'] == 'ACCEPTED';
    view = shopping_operation(p,'view',{},NOW);
    assert view['workspace']['profile']['max_transfers'] == 1;
}

test "changing a transfer limit invalidates an accepted bus visit" {
    p = transit_user(); plan = owned(p,ShoppingWorkspace).visit_plans[0];
    visit_action(p,{'key':plan['key'],'action':'accept','acknowledge_unknowns':True},NOW);
    shopping_operation(p,'update_profile',{'max_transfers':0},NOW);
    assert plan['status'] == 'NEEDS_REVIEW';
}

test "expired timetable evidence cannot be newly accepted" {
    p = transit_user(); plan = owned(p,ShoppingWorkspace).visit_plans[0];
    visit_view(p,'2026-10-27T12:16:00-04:00');
    assert plan['status'] == 'NEEDS_REVIEW' and not plan['accept_allowed'];
    failed = False;
    try { visit_action(p,{'key':plan['key'],'action':'accept','acknowledge_unknowns':True},'2026-10-27T12:16:00-04:00'); }
    except ValueError { failed = True; }
    assert failed;
}
