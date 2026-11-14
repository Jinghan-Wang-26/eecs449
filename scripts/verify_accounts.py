"""Offline real-HTTP verification of accounts, isolation, logout, and persistence.

Uses temporary databases and synthetic accounts; never loads local credentials.
Run with the project's Python environment: python scripts/verify_accounts.py.
"""
import json
import os
import sqlite3
import tempfile
import tomllib
from pathlib import Path

from verify_e2e import ROOT, Server, free_port


PASSWORD = 'Synthetic account password!'


def main():
    with tempfile.TemporaryDirectory(prefix='cartcompass-accounts-') as directory:
        work = Path(directory)
        settings = tomllib.loads((ROOT / 'app.toml').read_text())
        settings['data_mode'] = 'mock'
        (work / 'app.toml').write_text(''.join(f'{k} = {json.dumps(v)}\n' for k, v in settings.items()))
        env = dict(os.environ, JAC_DATA_PATH=str(work), CARTCOMPASS_SETTINGS=str(work / 'app.toml'),
                   CARTCOMPASS_ENV_LOADED='1', LLM_BACKEND='api', LLM_API_KEY='',
                   KROGER_CLIENT_ID='', KROGER_CLIENT_SECRET='', GEOAPIFY_API_KEY='',
                   SMTP_HOST='', SMTP_USER='', SMTP_PASSWORD='')
        server = Server(free_port(), env, work / 'server.log')
        def check(label, condition):
            if not condition:
                raise AssertionError(label)
            print('PASS  ' + label, flush=True)

        def account(name, password=PASSWORD, register=True):
            identity = {'type': 'username', 'value': name}
            credential = {'type': 'password', 'password': password}
            if register:
                code, payload = server.request('/user/register', {'identities': [identity], 'credential': credential})
                check('registration creates a named account without issuing a token', code == 201 and 'token' not in payload['data'])
            code, payload = server.request('/user/login', {'identity': identity, 'credential': credential})
            check('login issues a session', code == 200)
            return payload['data']

        def walker(name, data, token):
            code, payload = server.request('/walker/' + name, data, token)
            if code != 200 or not payload.get('ok'):
                raise AssertionError(f'{name} failed with HTTP {code}')
            reports = payload.get('data', {}).get('reports', [])
            if not reports:
                raise AssertionError(f'{name} returned no reports: {payload}')
            return reports[0]

        def shop(action, data, token):
            return walker('ShoppingAction', {'action': action, 'data': data}, token)

        try:
            server.start()
            names = ['ShoppingAction', 'ChatHistory', 'SendMessage', 'StartShoppingPlan',
                     'update_profile', 'update_interest', 'refresh_offers', 'build_candidates',
                     'plan_shopping', 'plan_action', 'feedback', 'discover_products',
                     'check_reminders', 'sync', 'chat', 'SessionInfo', 'LogoutSession']
            for name in names:
                check('anonymous API blocked: ' + name, server.request('/walker/' + name, {})[0] == 401)
            check('forged bearer rejected', server.request('/walker/ShoppingAction', {}, 'forged-token-' * 4)[0] == 401)
            check('guest cannot authenticate', server.request('/user/login', {
                'identity': {'type': 'username', 'value': '__guest__'},
                'credential': {'type': 'password', 'password': '__no_password__'}})[0] == 401)
            check('weak password rejected by server', server.request('/user/register', {
                'identities': [{'type': 'username', 'value': 'weak-user'}],
                'credential': {'type': 'password', 'password': 'short'}})[0] == 400)
            alice, bob = account('Alice'), account('Bob')
            a, b = alice['token'], bob['token']
            check('accounts have distinct graph roots', alice['root_id'] != bob['root_id'])
            check('duplicate normalized usernames rejected', server.request('/user/register', {
                'identities': [{'type': 'username', 'value': ' ALICE '}],
                'credential': {'type': 'password', 'password': PASSWORD}})[0] == 400)
            check('invalid password rejected', server.request('/user/login', {
                'identity': {'type': 'username', 'value': 'alice'},
                'credential': {'type': 'password', 'password': 'wrong password'}})[0] == 401)
            check('user info omits credentials', 'token' not in server.request('/user/info', token=a)[1]['data'])
            shop('update_profile', {'weekly_budget': 70, 'transport': ['WALK'], 'max_walk_min': 60,
                                    'carry_limit_kg': 20, 'free_windows': ['SAT 14:00-17:00']}, a)
            shop('save_interest', {'category': 'milk', 'qty': 2}, a)
            shop('save_interest', {'category': 'rice', 'qty': 1}, b)
            shop('expense_add', {'id': 'alice-receipt', 'amount': '4.25', 'store': 'Alice Test Market'}, a)
            shop('background', {'enabled': True}, a)
            plans = shop('plan', {}, a)['workspace']['plans']
            check('Alice can generate a shopping plan', bool(plans))
            walker('SendMessage', {'text': 'Alice private shopping conversation'}, a)
            walker('SendMessage', {'text': 'Bob private shopping conversation'}, b)
            av, bv = shop('view', {}, a), shop('view', {}, b)
            check('shopping needs are isolated', any(i['category'] == 'milk' for i in av['interests'])
                  and not any(i['category'] == 'milk' for i in bv['interests']))
            check('profiles and budgets are isolated', av['budget']['spent'] == 4.25 and bv['budget']['spent'] == 0)
            check('plans and notification preferences are isolated', bool(av['workspace']['plans'])
                  and not bv['workspace']['plans'] and not bv['background']['enabled'])
            ah = walker('ChatHistory', {}, a)
            bh = walker('ChatHistory', {}, b)
            check('chat histories are isolated', 'Alice private' in json.dumps(ah) and 'Alice private' not in json.dumps(bh))
            failed = shop('expense_void', {'id': 'alice-receipt'}, b)
            check('other account cannot change an expense by guessing its ID', 'error' in failed and shop('view', {}, a)['budget']['spent'] == 4.25)
            failed = shop('plan_action', {'key': plans[0]['key'], 'action': 'accept'}, b)
            check('other account cannot accept a plan by guessing its key', 'error' in failed)
            code, attack = server.request('/walker/ChatHistory/' + alice['root_id'], {}, b)
            check('explicit foreign root cannot expose chat', 'Alice private' not in json.dumps(attack)
                  and not attack.get('data', {}).get('reports'))
            code, attack = server.request('/walker/ShoppingAction/' + alice['root_id'],
                                         {'action': 'expense_void', 'data': {'id': 'alice-receipt'}}, b)
            check('explicit foreign root cannot mutate data', shop('view', {}, a)['budget']['spent'] == 4.25)
            code, attack = server.request('/walker/ShoppingAction', {'action': 'view', 'user_id': alice['root_id']}, b)
            check('client-supplied identity cannot switch accounts', 'Alice Test Market' not in json.dumps(attack))
            walker('ChatHistory', {'clear': True}, b)
            walker('StartShoppingPlan', {'request_id': 'bob-new-trip'}, b)
            check('clearing chat and starting a trip affect only the signed-in account', walker('ChatHistory', {}, a) == ah
                  and any(i['category'] == 'milk' for i in shop('view', {}, a)['interests']))
            # Possessing another session string in a logout body cannot revoke it.
            walker('LogoutSession', {'token': a}, b)
            check('logout revocation is bound to the authenticated account', server.request('/user/info', token=a)[0] == 200)
            walker('LogoutSession', {'token': a}, a)
            check('signed-out tokens are rejected by the server', server.request('/walker/ChatHistory', {}, a)[0] == 401)
            check('signing out Alice does not sign out Bob', server.request('/user/info', token=b)[0] == 200)
            alice = account('alice', register=False)
            a = alice['token']
            server.stop()
            server.start()
            check('accounts, sessions and separate graphs survive restart',
                  shop('view', {}, a)['budget']['spent'] == 4.25 and shop('view', {}, b)['budget']['spent'] == 0
                  and walker('ChatHistory', {}, a) == ah)
            code, _ = server.request('/user/password', {'username': 'alice', 'current_password': PASSWORD,
                                     'new_password': 'New synthetic password!'}, a, 'PUT')
            check('password changes invalidate existing sessions', code == 200 and server.request('/user/info', token=a)[0] == 401)
            alice = account('alice', password='New synthetic password!', register=False)
            with sqlite3.connect(work / '.jac/data/main.db') as db:
                check('passwords are stored as salted hashes', db.execute('SELECT password_hash FROM users WHERE username="alice"').fetchone()[0].startswith('scrypt$'))
                db.execute('UPDATE cartcompass_sessions SET expires_at=0 WHERE username="alice"')
            check('expired sessions cannot access the API', server.request('/walker/ShoppingAction', {}, alice['token'])[0] == 401)
            print('ALL ACCOUNT ISOLATION CHECKS PASSED', flush=True)
        except Exception:
            # Test logs contain synthetic data only, but retain them locally for debugging.
            destination = Path('/tmp/cartcompass-account-test-failure.log')
            destination.write_text((work / 'server.log').read_text())
            print('Test server log: ' + str(destination), flush=True)
            raise
        finally:
            server.stop()


if __name__ == '__main__':
    main()
