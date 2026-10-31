"""End-to-end check of the ledger, budget notes, background reminders and email delivery.

Starts an isolated `jac start` on a free port with its own data directory and a
settings file without quiet hours, plus a local fake SMTP server, then drives
the real HTTP API. Your own .jac/data and app.toml are never touched, and no
message leaves this machine. Offline (demo data); no API keys are needed.

    python scripts/verify_e2e.py                 # fresh, empty data directory
    python scripts/verify_e2e.py --copy-data     # a copy of your local .jac/data,
                                                 # to check old saved graphs still load

Exits 0 when every step passes. Takes about two minutes because it waits for
real scheduler ticks.
"""

import argparse
import json
import os
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
import urllib.request
import uuid
from datetime import date, timedelta
from email import message_from_bytes
from email.header import decode_header, make_header
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JAC = ROOT / '.venv' / 'bin' / 'jac'
ADDRESS = 'e2e-shopper@example.com'
received = []


class FakeSmtp(socketserver.StreamRequestHandler):
    """Just enough SMTP for smtplib: EHLO, AUTH PLAIN/LOGIN, MAIL, RCPT, DATA, QUIT."""

    def reply(self, line):
        self.wfile.write((line + '\r\n').encode())

    def handle(self):
        self.reply('220 fake-smtp ready')
        rcpt, data, reading = [], [], False
        for raw in self.rfile:
            line = raw.decode(errors='replace').rstrip('\r\n')
            if reading:
                if line == '.':
                    reading = False
                    msg = message_from_bytes('\r\n'.join(data).encode())
                    received.append({'to': rcpt, 'title': str(make_header(decode_header(msg['Subject'] or ''))),
                                     'body': msg.get_payload(decode=True).decode(errors='replace')})
                    rcpt, data = [], []
                    self.reply('250 queued')
                else:
                    data.append(line[1:] if line.startswith('..') else line)
                continue
            verb = line.split(' ', 1)[0].upper()
            if verb == 'EHLO':
                self.reply('250-fake-smtp'); self.reply('250 AUTH PLAIN LOGIN')
            elif verb == 'AUTH':
                if line.upper().startswith('AUTH LOGIN') and len(line.split()) == 2:
                    self.reply('334 VXNlcm5hbWU6'); self.rfile.readline()
                    self.reply('334 UGFzc3dvcmQ6'); self.rfile.readline()
                self.reply('235 authenticated')
            elif verb == 'RCPT':
                rcpt.append(line.split(':', 1)[1].strip(' <>')); self.reply('250 ok')
            elif verb == 'DATA':
                reading = True; self.reply('354 end with .')
            elif verb == 'QUIT':
                self.reply('221 bye'); return
            else:
                self.reply('250 ok')


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Server:
    def __init__(self, port, env, log_path):
        self.port, self.env, self.log_path, self.proc = port, env, log_path, None

    def start(self):
        log = open(self.log_path, 'a')
        self.proc = subprocess.Popen([str(JAC), 'start', '--port', str(self.port)], cwd=ROOT,
                                     env=self.env, stdout=log, stderr=subprocess.STDOUT)
        deadline = time.time() + 120
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError('server exited during startup; see ' + str(self.log_path))
            try:
                urllib.request.urlopen(f'http://127.0.0.1:{self.port}/', timeout=2)
                return
            except OSError:
                time.sleep(1)
        raise RuntimeError('server did not become ready')

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def call(self, action, data=None):
        request = urllib.request.Request(
            f'http://127.0.0.1:{self.port}/walker/ShoppingAction', method='POST',
            data=json.dumps({'action': action, 'data': data or {}}).encode(),
            headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=120) as response:
            envelope = json.load(response)
        reports = (envelope.get('data') or {}).get('reports') or []
        if not reports:
            raise AssertionError(f'{action}: no report in response {envelope}')
        return reports[0]


class Checks:
    def __init__(self):
        self.failed = 0

    def step(self, name, condition, detail=''):
        mark = 'PASS' if condition else 'FAIL'
        self.failed += 0 if condition else 1
        print(f'{mark}  {name}' + (f'  ({detail})' if detail and not condition else ''))
        return condition


def wait_for(predicate, timeout, interval=2):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return predicate()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--copy-data', action='store_true', help='start from a copy of the local .jac/data')
    parser.add_argument('--keep', action='store_true', help='keep the temporary directory for inspection')
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix='cartcompass-e2e-'))
    (work / '.jac').mkdir()
    if args.copy_data and (ROOT / '.jac' / 'data').is_dir():
        shutil.copytree(ROOT / '.jac' / 'data', work / '.jac' / 'data')
    settings = tomllib.loads((ROOT / 'app.toml').read_text())
    settings.update({'quiet_hours_start': 0, 'quiet_hours_end': 0, 'background_check_minutes': 5})
    (work / 'app.toml').write_text(''.join(
        f'{k} = {json.dumps(v) if not isinstance(v, bool) else str(v).lower()}\n' for k, v in settings.items()))

    smtp = socketserver.ThreadingTCPServer(('127.0.0.1', free_port()), FakeSmtp)
    smtp.daemon_threads = True
    threading.Thread(target=smtp.serve_forever, daemon=True).start()
    env = dict(os.environ, JAC_DATA_PATH=str(work), CARTCOMPASS_SETTINGS=str(work / 'app.toml'),
               CARTCOMPASS_ENV_LOADED='1', LLM_API_KEY='', KROGER_CLIENT_ID='', KROGER_CLIENT_SECRET='',
               GEOAPIFY_API_KEY='', SMTP_HOST='127.0.0.1', SMTP_PORT=str(smtp.server_address[1]),
               SMTP_USER='e2e@example.com', SMTP_PASSWORD='e2e-password', SMTP_FROM='cartcompass@example.com')
    server = Server(free_port(), env, work / 'server.log')
    check = Checks()
    print(f'Isolated run in {work} ({"copy of local data" if args.copy_data else "fresh data"})')
    try:
        server.start()
        view = server.call('view')
        check.step('server loads the graph and returns budget, delivery and background state',
                   'error' not in view and all(k in view for k in ('budget', 'delivery', 'background')), view.get('error', ''))
        server.call('set_mode', {'mode': 'mock'})
        out = server.call('update_profile', {'weekly_budget': '50', 'carry_limit_kg': '20', 'max_walk_min': '30',
                                             'transport': ['WALK', 'BUS'], 'free_windows': ['SAT 14:00-17:00']})
        check.step('profile saves a weekly budget', out.get('message') == 'Profile saved.', out.get('error', ''))
        start = out['budget']['spent']

        # Ledger: add, idempotent retry, correction with history, void.
        entry = {'id': 'e2e-' + uuid.uuid4().hex, 'amount': '12.50', 'store': 'E2E Market', 'category': 'milk'}
        out = server.call('expense_add', entry)
        check.step('an expense is recorded', out.get('message') == 'Expense recorded.'
                   and round(out['budget']['spent'] - start, 2) == 12.5, out.get('error', ''))
        out = server.call('expense_add', entry)
        check.step('retrying the same request does not double count', out.get('message') == 'Expense already recorded.'
                   and round(out['budget']['spent'] - start, 2) == 12.5)
        out = server.call('expense_correct', {'id': entry['id'], 'amount': '10'})
        row = [e for e in out['budget']['entries'] if e['id'] == entry['id']][0]
        check.step('a correction keeps the previous amount', round(out['budget']['spent'] - start, 2) == 10
                   and [h['amount'] for h in row['history']] == [12.5])
        out = server.call('expense_add', {'id': 'e2e-' + uuid.uuid4().hex, 'amount': '1', 'spent_at': '2099-01-01'})
        check.step('a future-dated expense is rejected', 'error' in out)

        # Budget notes on demo plans: leave less than the cheapest plan.
        server.call('expense_add', {'id': 'e2e-' + uuid.uuid4().hex, 'amount': f"{50 - start - 10 - 3:.2f}"})
        server.call('save_interest', {'category': 'rice', 'qty': 1})
        out = server.call('plan')
        plans = out['workspace']['plans']
        notes = out['workspace'].get('budget_notes', {})
        check.step('demo plans over the remaining budget carry a note', bool(plans)
                   and all(notes.get(p['key'], '').startswith('Estimated $') for p in plans if p['total'] > 3),
                   out.get('error') or f'{len(plans)} plans, notes={notes}')

        # Reminders: a due replenishment, then email delivery by the scheduler.
        bought = (date.today() - timedelta(days=10)).isoformat()
        out = server.call('save_interest', {'category': 'milk', 'kind': 'REPLENISH', 'replenishment_days': '7',
                                            'last_purchased_at': bought})
        check.step('a due replenishment creates an in-app reminder',
                   any(r['kind'] == 'REPLENISH' for r in out['reminders']), out.get('error', ''))
        out = server.call('notify_settings', {'email': ADDRESS, 'email_enabled': True})
        check.step('email settings save', out.get('message') == 'Email settings saved.', out.get('error', ''))
        out = server.call('notify_test', {})
        check.step('a test email reaches the SMTP server', out.get('message') == 'Test email sent.'
                   and any(m['title'] == 'CartCompass test' and m['to'] == [ADDRESS] for m in received), out.get('error', ''))
        out = server.call('background', {'enabled': True})
        check.step('background checks turn on', out['background']['enabled'])

        print('...waiting for the scheduler (up to 150 s)')
        digest = wait_for(lambda: [m for m in received if m['to'] == [ADDRESS] and 'milk' in m['body']
                                   and m['title'] != 'CartCompass test'], 150)
        check.step('the scheduler emails the reminder digest', bool(digest),
                   f'messages received: {[m["title"] for m in received]}')
        view = wait_for(lambda: (lambda v: v if v['background']['runs'] >= 1 else None)(server.call('view')), 90)
        check.step('the background run and delivery receipt are saved', bool(view)
                   and view['delivery']['last_delivery'].get('count', 0) >= 1)
        count = len([m for m in received if m['title'] != 'CartCompass test'])
        time.sleep(70)
        check.step('the same reminder is not emailed again on the next tick',
                   len([m for m in received if m['title'] != 'CartCompass test']) == count)

        # Persistence across a restart.
        before = server.call('view')
        server.stop()
        server.start()
        after = server.call('view')
        check.step('ledger, settings and background state survive a restart',
                   after['budget']['spent'] == before['budget']['spent']
                   and len(after['budget']['entries']) == len(before['budget']['entries'])
                   and after['delivery']['email'] == ADDRESS and after['background']['enabled'])
        log = (work / 'server.log').read_text()
        check.step('the server log has no tracebacks or failed background checks',
                   'Traceback' not in log and 'Background reminder check failed' not in log)
    except Exception as err:
        check.step('run completed', False, f'{type(err).__name__}: {err}')
    finally:
        server.stop()
        smtp.shutdown()
        if args.keep or check.failed:
            print(f'Kept {work} for inspection (server.log).')
        else:
            shutil.rmtree(work, ignore_errors=True)
    print('ALL PASSED' if not check.failed else f'{check.failed} FAILED')
    return 1 if check.failed else 0


if __name__ == '__main__':
    sys.exit(main())
