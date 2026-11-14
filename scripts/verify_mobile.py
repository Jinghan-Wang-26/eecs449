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
                    viewport={'width': 390, 'height': 844}, is_mobile=True, has_touch=True, device_scale_factor=1)
                page = context.new_page()
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.goto(url)
                expect(page.get_by_role('heading', name='Welcome to CartCompass')).to_be_visible()
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
                print('PASS reconnect validates account, logout revokes session and second account stays isolated', flush=True)

                # Chromium appinstalled is browser-owned; simulate only the UI event here.
                page.evaluate("window.dispatchEvent(new Event('appinstalled'))")
                expect(page.get_by_role('button', name='Install app', exact=True)).not_to_be_visible()
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
