"""Exercise populated shopping cards, not only an empty workspace.

Uses synthetic policy fixtures and intercepts the browser's ShoppingAction response;
no personal data or retailer/model credentials are used or changed.
"""
import copy
import json
import os
import subprocess

from playwright.sync_api import expect
from verify_e2e import ROOT, JAC


def check_bounds(page, width, stage):
    # The old panel hid overflow, so document.scrollWidth alone missed clipped cards.
    failures = page.evaluate("""() => {
        const panel = document.querySelector('.shopping-panel');
        const box = panel.getBoundingClientRect();
        const failures = [];
        if (document.documentElement.scrollWidth > window.innerWidth + 1) failures.push('page wider than viewport');
        for (const element of panel.querySelectorAll('.workspace-content *')) {
            const rect = element.getBoundingClientRect();
            if (!rect.width || !rect.height || !element.checkVisibility({checkVisibilityCSS: true})) continue;
            if (element.closest('svg') || getComputedStyle(element).position === 'fixed') continue;
            if (rect.right > box.right + 1 || rect.left < box.left - 1) {
                failures.push(element.tagName + '.' + element.className + ': outside panel');
            }
        }
        for (const card of panel.querySelectorAll('.plan-best, .metrics, .plan-alt, .visit-details, .accept-panel')) {
            if (card.getClientRects().length && card.clientWidth && card.scrollWidth > card.clientWidth + 1) {
                failures.push(card.className + ': content clipped inside card');
            }
        }
        return [...new Set(failures)];
    }""")
    assert not failures, (width, stage, failures)


def verify_plan_layout(page, context, url):
    result = subprocess.run([str(JAC), 'run', 'scripts/ui_plan_fixture.jac'], cwd=ROOT,
                            env=dict(os.environ, CARTCOMPASS_ENV_LOADED='1', LLM_API_KEY='',
                                     GEOAPIFY_API_KEY='', KROGER_CLIENT_ID='', KROGER_CLIENT_SECRET=''),
                            text=True, capture_output=True, check=True, timeout=60)
    plans = json.loads(result.stdout.strip().splitlines()[-1])
    token = page.evaluate('localStorage.getItem("jac_token")')
    response = context.request.post(url + '/walker/ShoppingAction',
                                    headers={'Authorization': 'Bearer ' + token}, data={'action': 'view'})
    assert response.ok
    payload = response.json()
    snapshot = payload['data']['reports'][0]
    ws = snapshot['workspace']
    ws['visit_plans'] = plans
    ws['profile'].update(address=plans[0]['origin_label'], transport=['BUS'], free_windows=['TUE 14:00-16:00'])
    ws['visit_search'] = {'generated_at': '2030-01-01T10:00:00-05:00', 'checked_stores': 4, 'nearby_count': 4}
    ws['notices'] = []
    ws['budget_notes'] = {}
    snapshot['message'] = 'Synthetic responsive-layout fixture.'

    def shopping_fixture(route):
        route.fulfill(status=200, json=copy.deepcopy(payload))

    page.route('**/walker/ShoppingAction', shopping_fixture)
    try:
        page.emulate_media(reduced_motion='reduce')
        page.reload()
        page.get_by_role('button', name='Plan', exact=True).click()
        expect(page.locator('.plan-best')).to_be_visible(timeout=30000)
        expect(page.locator('.plan-best .plan-name')).to_have_text(plans[0]['store']['name'])
        illustration = context.request.get(url + '/static/illustrations/grocery-trip.svg')
        assert illustration.ok and 'svg' in illustration.headers['content-type']
        widths = [320, 360, 390, 430, 600, 768, 860, 900, 1024, 1280, 1440]
        for width in widths:
            page.set_viewport_size({'width': width, 'height': 900})
            # Test both folded and expanded evidence, including long names and tax notes.
            check_bounds(page, width, 'options')
            expect(page.locator('.plan-best')).to_contain_text('fare unknown')
            expect(page.locator('.plan-best .breakdown')).to_contain_text('Unknown')
            page.get_by_text('Full plan details', exact=True).click()
            expect(page.locator('.plan-best .visit-details')).to_be_visible()
            check_bounds(page, width, 'expanded plan')
            page.get_by_text('Full plan details', exact=True).click()
            if width in (320, 390, 768, 1280):
                page.evaluate('window.scrollTo(0, 0)')
                page.screenshot(path=f'/tmp/cartcompass-ui/options-{width}.png', full_page=True, animations='disabled')
            # The main action must be reachable, not hidden outside the card.
            page.get_by_role('button', name='Review route', exact=False).click()
            expect(page.get_by_role('region', name='Accept this plan')).to_be_visible()
            check_bounds(page, width, 'route and acceptance')
            page.get_by_role('tab', name='Options', exact=False).click()
            expect(page.locator('.plan-best')).to_be_visible()
        # Phone landscape and browser text zoom also need to reflow.
        page.set_viewport_size({'width': 844, 'height': 390})
        check_bounds(page, 844, 'landscape')
        page.set_viewport_size({'width': 390, 'height': 844})
        page.evaluate("document.body.style.zoom = '1.25'")
        check_bounds(page, 390, '125% zoom')
        page.evaluate("document.body.style.zoom = ''")
        page.evaluate("window.dispatchEvent(new Event('appinstalled'))")
        check_bounds(page, 390, 'installed app shell')
        print('PASS populated plans at 11 widths (320-1440px), expanded evidence, route controls, landscape and 125% zoom', flush=True)
    finally:
        page.unroute('**/walker/ShoppingAction', shopping_fixture)
        page.evaluate("document.body.style.zoom = ''")
