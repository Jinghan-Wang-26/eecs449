# Background reminders and email

CartCompass can check for reminders on a schedule and email new ones to you, even when no CartCompass page is open. The server (`jac start`) must keep running for this to work. On a phone, the normal mail app shows these emails as notifications, so no extra app is needed.

## How it works

1. `server/background.jac` runs on the Jac `@schedule` scheduler once a minute.
2. For each user who turned on **Check for reminders in the background**, it runs the same refresh as **Refresh tools** every `background_check_minutes` (default 30, in `app.toml`). Quiet hours skip the refresh.
3. On every tick, `notify/delivery.jac` emails due reminders that have not been emailed yet:
   - one digest email per check (at most 5 reminders listed),
   - each reminder at most once,
   - nothing during quiet hours,
   - a failed send retries after 5 minutes, then 10, 20, and so on, at most every 6 hours.
4. Changing the email address resets the receipts, so the new address gets the current reminders.

Reminders still appear in the app as before: a banner, plus a browser notification if you allowed it.

## Email setup (SMTP)

The server needs an SMTP account to send from. For Gmail, turn on 2-step verification and create an [app password](https://myaccount.google.com/apppasswords). Do not use your normal password. Add the settings to the local `.env` and restart `jac start`:

```dotenv
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your.address@gmail.com
SMTP_PASSWORD=your-16-character-app-password
SMTP_FROM=your.address@gmail.com
```

Port 587 uses STARTTLS and port 465 uses SSL. Only a loopback test server (`127.0.0.1` or `localhost`) is contacted without TLS.

Then, in CartCompass, open **My list → Discoveries & reminders**, enter the address that should receive reminders, tick **Email me new reminders**, click **Save email settings**, and click **Send test email**. The receiving address can be any inbox, not only the sending account.

## Limits

- Email is sent only while the local server runs. A laptop that is asleep sends nothing; reminders go out at the next tick after it wakes.
- This is a local single-user setup. A hosted multi-user deployment would need per-user authentication, rate limits and a managed email provider.
- SMS and app push notifications are not implemented.

## Tests

```bash
python -m unittest tests.test_channels
jac test tests/test_delivery.jac tests/test_background.jac
python scripts/verify_e2e.py   # isolated server and a local fake SMTP server; about two minutes
```

The unit tests replace the sender. The end-to-end script sends to a local fake SMTP server, so no email leaves the machine.
