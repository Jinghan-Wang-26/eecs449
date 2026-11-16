"""Browser verification of the installable app and its personal-data boundary.

Run with Playwright installed; see docs/MOBILE_APP.md. Starts an isolated Jac
server with synthetic accounts and no external API credentials. Never uses the
local app's databases. Optional CHROMIUM_EXECUTABLE_PATH selects an installed
Chromium; otherwise Playwright uses its managed browser.
"""
import json
import os
import tempfile
import tomllib
from pathlib import Path

from playwright.sync_api import expect, sync_playwright
from verify_e2e import ROOT, Server, free_port


PASSWORD = 'Mobile browser test password!'


def main():
    Path('/tmp/cartcompass-ui').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cartcompass-mobile-') as directory:
        work = Path(directory)
        cfg = tomllib.loads((ROOT / 'app.toml').read_text())
        cfg['data_mode'] = 'mock'
        (work / 'app.toml').write_text(''.join(f'{k} = {json.dumps(v)}\n' for k, v in cfg.items()))
        env = dict(os.environ, JAC_DATA_PATH=str(work), CARTCOMPASS_SETTINGS=str(work / 'app.toml'),
                   CARTCOMPASS_ENV_LOADED='1', LLM_BACKEND='api', LLM_API_KEY='',
                   GEOAPIFY_API_KEY='', KROGER_CLIENT_ID='', KROGER_CLIENT_SECRET='',
                   SMTP_HOST='', SMTP_USER='', SMTP_PASSWORD='')
        server = Server(free_port(), env, work / 'server.log')
        try:
            server.start()
            url = f'http://127.0.0.1:{server.port}'
            with sync_playwright() as p:
                launch = {'headless': True, 'args': ['--no-sandbox']}
                if os.environ.get('CHROMIUM_EXECUTABLE_PATH'):
                    launch['executable_path'] = os.environ['CHROMIUM_EXECUTABLE_PATH']
                # Installation is disabled in incognito contexts. Use an isolated,
                # temporary regular profile for real eligibility checks.
                context = p.chromium.launch_persistent_context(str(work / 'browser-profile'), **launch,
                    locale='zh-CN', viewport={'width': 390, 'height': 844}, is_mobile=True, has_touch=True, device_scale_factor=1)
                page = context.new_page()
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.goto(url)
                expect(page.get_by_role('heading', name='Welcome to CartCompass')).to_be_visible()
                assert page.evaluate('navigator.language') == 'zh-CN'
                expect(page.locator('html')).to_have_attribute('lang', 'en')
                expect(page.locator('html')).to_have_attribute('translate', 'no')
                expect(page.locator('meta[name="google"]')).to_have_attribute('content', 'notranslate')
                page.get_by_role('button', name='Sign in', exact=True).click()
                assert page.get_by_label('Username', exact=True).evaluate('(el) => el.validationMessage') == 'Please fill out this field.'
                page.get_by_label('Username', exact=True).fill('valid-user')
                assert page.get_by_label('Username', exact=True).evaluate('(el) => el.validationMessage') == ''
                page.get_by_label('Username', exact=True).fill('')
                print('PASS English page and required-field messages with zh-CN browser locale', flush=True)
                page.evaluate('navigator.serviceWorker.ready')
                page.wait_for_function('navigator.serviceWorker.controller !== null')
                assert page.evaluate('navigator.serviceWorker.controller.scriptURL') == url + '/cartcompass-sw.js'
                manifest_url = page.locator('link[rel="manifest"]').get_attribute('href')
                manifest_response = context.request.get(url + manifest_url)
                assert manifest_response.ok
                manifest = manifest_response.json()
                assert manifest['display'] == 'standalone' and manifest['start_url'] == '/'
                assert manifest['scope'] == '/' and manifest['id'] == '/'
                for icon in manifest['icons']:
                    response = context.request.get(url + icon['src'])
                    assert response.ok and response.headers['content-type'].startswith('image/png')
                    width = int.from_bytes(response.body()[16:20], 'big')
                    assert icon['sizes'] == f'{width}x{width}'
                cdp = context.new_cdp_session(page)
                install_errors = cdp.send('Page.getInstallabilityErrors')['installabilityErrors']
                assert not install_errors, install_errors
                print('PASS manifest, icons, root worker scope and Chromium installability', flush=True)

                # Exercise manual help independently of whether headless Chrome offers a prompt.
                page.evaluate("window.__ccPrompt = new Event('beforeinstallprompt', {cancelable: true}); window.__ccPrompt.prompt = async () => {}; window.__ccPrompt.userChoice = Promise.resolve({outcome: 'dismissed'}); window.dispatchEvent(window.__ccPrompt)")
                page.get_by_role('button', name='Install app', exact=True).click()
                expect(page.get_by_text('You can install later from your browser menu.')).to_be_visible()
                page.get_by_role('button', name='Install app', exact=True).click()
                expect(page.get_by_role('dialog')).to_be_visible()
                expect(page.get_by_text('iPhone / iPad:', exact=True)).to_be_visible()
                page.get_by_role('button', name='Close installation help').click()
                expect(page.get_by_role('dialog')).not_to_be_visible()
                assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
                page.screenshot(path='/tmp/cartcompass-pwa-login.png', full_page=True, animations='disabled')
                print('PASS install prompt dismissal, Safari/Android help and phone login layout', flush=True)

                def signup(name):
                    page.get_by_role('button', name='Create an account', exact=True).click()
                    page.get_by_label('Username', exact=True).fill(name)
                    page.get_by_label('Password', exact=True).fill(PASSWORD)
                    page.get_by_label('Confirm password', exact=True).fill(PASSWORD)
                    page.get_by_role('button', name='Create account', exact=True).click()
                    expect(page.locator('.account-name')).to_have_text(name, timeout=30000)

                signup('mobile-alice')
                expect(page.locator('.welcome-art')).to_be_visible()
                page.wait_for_function("document.querySelector('.welcome-art')?.naturalWidth > 0")
                page.screenshot(path='/tmp/cartcompass-ui/welcome-390.png', full_page=True, animations='disabled')
                # Guided setup must work without a model or retailer credential.
                page.get_by_role('button', name="I'd rather add items myself", exact=True).click()
                expect(page.get_by_label('Item', exact=True)).to_be_visible()
                expect(page.get_by_role('button', name='Add items to continue →')).to_be_disabled()
                expect(page.locator('.list-placeholder img')).to_be_visible()
                page.screenshot(path='/tmp/cartcompass-ui/empty-list-390.png', full_page=True, animations='disabled')
                page.get_by_label('Item', exact=True).fill('milk')
                page.get_by_label('Packages', exact=True).fill('0')
                page.get_by_role('button', name='Add to list', exact=True).click()
                assert page.get_by_label('Packages', exact=True).evaluate('(el) => el.validationMessage') == 'Please enter a value greater than or equal to 1.'
                expect(page.locator('.shopping-items .item-name')).to_have_count(0)
                page.get_by_label('Packages', exact=True).fill('1.5')
                page.get_by_role('button', name='Add to list', exact=True).click()
                assert page.get_by_label('Packages', exact=True).evaluate('(el) => el.validationMessage') == 'Please enter a value in increments of 1.'
                page.get_by_label('Packages', exact=True).fill('2')
                assert page.get_by_label('Packages', exact=True).evaluate('(el) => el.validationMessage') == ''
                page.get_by_role('button', name='Add to list', exact=True).click()
                expect(page.locator('.shopping-items .item-name')).to_have_text('milk')
                expect(page.locator('.shopping-panel')).to_be_visible()
                expect(page.get_by_label('Item', exact=True)).to_be_focused()
                expect(page.get_by_role('button', name='Add starting point →')).to_be_enabled()
                expect(page.get_by_label('Trip details', exact=True)).to_contain_text('2 details to add')
                page.get_by_role('button', name='Add starting point →').click()
                expect(page.get_by_label('Type a start address')).to_be_visible()
                expect(page.locator('#trip-start')).to_be_focused()
                expect(page.get_by_label('Carrying limit', exact=True)).not_to_be_visible()
                page.get_by_role('button', name='← Back to trip', exact=True).click()
                page.get_by_role('button', name='Edit shopping time', exact=True).click()
                expect(page.locator('#trip-time')).to_be_focused()
                page.get_by_role('button', name='+ Add a time', exact=True).click()
                page.get_by_label('Budget', exact=True).fill('65')
                page.get_by_role('button', name='Save preferences', exact=True).click()
                expect(page.locator('.shopping-items .item-name')).to_have_text('milk')
                expect(page.get_by_label('Trip details', exact=True)).to_contain_text('1 detail to add')
                expect(page.get_by_role('button', name='Edit shopping time')).to_contain_text('Sat 14:00–17:00')
                page.get_by_role('button', name='Not this trip', exact=True).click()
                expect(page.get_by_role('button', name='Add items to continue →')).to_be_disabled()
                page.get_by_role('button', name='Add back', exact=True).click()
                expect(page.get_by_role('button', name='Add starting point →')).to_be_enabled()
                page.get_by_role('button', name='Ask assistant ↗', exact=True).click()
                expect(page.get_by_label('Message your shopping assistant')).to_be_focused()
                page.get_by_role('button', name='Set my budget', exact=True).click()
                expect(page.get_by_label('Message your shopping assistant')).to_have_value('My weekly budget is $')
                page.get_by_label('Message your shopping assistant').fill('')
                page.get_by_role('button', name='Plan', exact=True).click()
                for width, height in [(320, 740), (390, 844), (1280, 900)]:
                    page.set_viewport_size({'width': width, 'height': height})
                    page.evaluate('window.scrollTo(0, 0)')
                    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), width
                    if width < 861:
                        nav = page.locator('.pane-switch').bounding_box()
                        assert nav and nav['y'] + nav['height'] <= height
                        assert nav['y'] >= height - 100
                        page.screenshot(path=f'/tmp/cartcompass-ui/mobile-{width}.png', full_page=True, animations='disabled')
                    else:
                        page.screenshot(path='/tmp/cartcompass-ui/desktop.png', full_page=True, animations='disabled')
                page.set_viewport_size({'width': 390, 'height': 844})
                page.get_by_role('button', name='+ New trip', exact=True).click()
                expect(page.get_by_role('dialog', name='Start a new shopping trip?')).to_be_visible()
                page.get_by_role('button', name='Keep this trip', exact=True).click()
                expect(page.locator('.shopping-items .item-name')).to_have_text('milk')
                page.get_by_role('button', name='+ New trip', exact=True).click()
                page.get_by_role('button', name='Start new trip', exact=True).click()
                expect(page.get_by_role('dialog', name='Start a new shopping trip?')).not_to_be_visible(timeout=30000)
                # New trips keep the saved profile, but start a separate list.
                opener = page.get_by_role('button', name='Open the workspace', exact=True)
                expect(opener).to_be_visible()
                opener.click()
                expect(page.locator('.shopping-items .item-name')).to_have_count(0)
                expect(page.get_by_label('Trip details', exact=True)).to_contain_text('1 detail to add')
                expect(page.get_by_role('button', name='Add to this trip', exact=True)).not_to_be_visible()
                page.get_by_text('From earlier trips', exact=True).click()
                expect(page.get_by_role('button', name='Add to this trip', exact=True)).to_be_visible()
                page.get_by_role('button', name='Add to this trip', exact=True).click()
                expect(page.locator('.shopping-items .item-name')).to_have_text('milk')
                print('PASS guided list entry, missing-detail navigation, saved preferences, mobile dock and deliberate trip reset', flush=True)

                token = page.evaluate('localStorage.getItem("jac_token")')
                headers = {'Authorization': 'Bearer ' + token}
                assert context.request.post(url + '/walker/SendMessage', headers=headers,
                                            data={'text': 'Alice private mobile conversation'}).ok
                assert context.request.post(url + '/walker/ShoppingAction', headers=headers,
                                            data={'action': 'save_interest', 'data': {'category': 'milk', 'qty': 2}}).ok
                page.reload()
                expect(page.locator('.account-name')).to_have_text('mobile-alice')
                page.get_by_role('button', name='Assistant', exact=True).click()
                expect(page.get_by_text('Alice private mobile conversation', exact=True)).to_be_visible(timeout=30000)
                # Cover narrow phones and a desktop without hiding overflow in CSS.
                for width, height in [(320, 740), (390, 844), (1280, 900)]:
                    page.set_viewport_size({'width': width, 'height': height})
                    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), width
                page.set_viewport_size({'width': 390, 'height': 844})
                page.get_by_role('button', name='Plan', exact=True).click()
                page.wait_for_function("getComputedStyle(document.querySelector('.shopping-panel')).opacity === '1'")
                page.screenshot(path='/tmp/cartcompass-pwa-workspace.png', full_page=True, animations='disabled')
                page.get_by_role('button', name='Assistant', exact=True).click()
                print('PASS phone sign-up, shopping list, conversation and Plan/Assistant navigation', flush=True)

                # A localized browser error must not become user-facing application text.
                page.evaluate("""() => {
                    window.__originalFetch = window.fetch;
                    window.fetch = (...args) => String(args[0]).includes('/walker/SendMessage')
                        ? Promise.reject(new TypeError('\\u7f51\\u7edc\\u9519\\u8bef')) : window.__originalFetch(...args);
                }""")
                page.get_by_label('Message your shopping assistant').fill('Please help with this trip')
                page.get_by_role('button', name='Send', exact=False).click()
                expect(page.get_by_text('The chat request failed. Check your connection and try again.', exact=True)).to_be_visible()
                page.evaluate('window.fetch = window.__originalFetch; delete window.__originalFetch')
                print('PASS English dynamic quantity validation, recovery and localized network-error handling', flush=True)

                # Inspect actual Cache Storage after private responses have flowed through it.
                cache_data = page.evaluate("""async () => {
                    const result = [];
                    for (const name of await caches.keys()) {
                        const cache = await caches.open(name);
                        for (const request of await cache.keys()) {
                            const response = await cache.match(request);
                            result.push({name, url: request.url, text: response.headers.get('content-type').includes('text') ? await response.text() : ''});
                        }
                    }
                    return result;
                }""")
                assert cache_data and len(cache_data) == 4
                for item in cache_data:
                    assert item['url'].startswith(url + '/static/mobile/')
                    assert token not in item['text'] and 'Alice private' not in item['text']
                    assert 'mobile-alice' not in item['text']
                await_ready = 'navigator.serviceWorker.ready'
                page.evaluate(await_ready)
                context.set_offline(True)
                expect(page.get_by_text('You are offline', exact=True)).to_be_visible()
                expect(page.get_by_role('button', name='Sign out', exact=True)).to_be_disabled()
                expect(page.get_by_label('Message your shopping assistant')).to_be_disabled()
                result = page.evaluate("""async () => {
                    try { await fetch('/user/info', {headers: {Authorization: 'Bearer ' + localStorage.getItem('jac_token')}}); return 'cached'; }
                    catch { return 'network-required'; }
                }""")
                assert result == 'network-required'
                page.reload()
                expect(page.get_by_role('heading', name='You are offline')).to_be_visible()
                expect(page.locator('html')).to_have_attribute('translate', 'no')
                assert 'Alice private' not in page.content() and 'mobile-alice' not in page.content()
                page.screenshot(path='/tmp/cartcompass-pwa-offline.png', full_page=True, animations='disabled')
                print('PASS private data absent from caches, offline actions disabled, public fallback on relaunch', flush=True)
                context.set_offline(False)
                page.get_by_role('link', name='Try again').click()
                expect(page.locator('.account-name')).to_have_text('mobile-alice', timeout=30000)
                page.get_by_role('button', name='Sign out', exact=True).click()
                expect(page.get_by_role('heading', name='Welcome to CartCompass')).to_be_visible(timeout=30000)
                assert context.request.get(url + '/user/info', headers=headers).status == 401
                signup('mobile-bob')
                assert 'Alice private' not in page.content()
                # Simulate a saved chat update without calling a paid language model.
                bob_token = page.evaluate('localStorage.getItem("jac_token")')
                assert context.request.post(url + '/walker/ShoppingAction', headers={'Authorization': 'Bearer ' + bob_token},
                                            data={'action': 'save_interest', 'data': {'category': 'rice', 'qty': 1}}).ok
                page.evaluate("window.dispatchEvent(new CustomEvent('shopping-chat-updated', {detail: 'chat'}))")
                expect(page.locator('.pane-switch button').filter(has_text='Assistant')).to_have_attribute('aria-pressed', 'true')
                expect(page.locator('.assistant-panel')).to_be_visible()
                expect(page.locator('.shopping-panel')).not_to_be_visible()
                print('PASS reconnect validates account, logout revokes session and second account stays isolated', flush=True)

                # Chromium appinstalled is browser-owned; simulate only the UI event here.
                page.evaluate("window.dispatchEvent(new Event('appinstalled'))")
                expect(page.get_by_role('button', name='Install app', exact=True)).not_to_be_visible()
                from verify_plan_layout import verify_plan_layout
                verify_plan_layout(page, context, url)
                assert not errors, errors
                print('PASS installed-state UI and no browser JavaScript errors', flush=True)
                context.close()
        except Exception:
            if (work / 'server.log').exists():
                Path('/tmp/cartcompass-mobile-test-failure.log').write_text((work / 'server.log').read_text())
            raise
        finally:
            server.stop()


if __name__ == '__main__':
    main()
