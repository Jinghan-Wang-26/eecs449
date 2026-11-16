"""Outbound reminder delivery by SMTP email (stdlib only).

Server-side settings come from the local .env:
  SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASSWORD, SMTP_FROM
Port 465 uses SSL; other ports use STARTTLS. Only a loopback host (a local test
server) may skip TLS. Credentials are never returned to the browser or written
to the graph.
"""
import re;
import smtplib;
import ssl;
import from email.message { EmailMessage }
import from integrations.providers { credentials }
glob EMAIL = re.compile('^[^@\\s]{1,64}@[^@\\s]{1,190}\\.[A-Za-z]{2,}$');
glob LOOPBACK = ('127.0.0.1', 'localhost');
class ChannelError(ValueError) {}
def setting(name: any, `default: any = '') -> any {
    return (credentials().get(name, '') or `default);
}
def channel_status() -> any {
    return {
        'email': all(setting(k) for k in ('SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD'))
    };
}
def valid_email(address: any) -> any {
    return bool(EMAIL.match((address or '')));
}
def send_email(`to: any, subject: any, body: any, timeout: any = 15) -> any {
    if not valid_email(`to) {
        raise ChannelError('Enter a valid email address.');
    }
    if not channel_status()['email'] {
        raise ChannelError(
            'Email is not configured on this server (SMTP_HOST, SMTP_USER, SMTP_PASSWORD).'
        );
    }
    host = setting('SMTP_HOST');
    message = EmailMessage();
    message['From'] = setting('SMTP_FROM') or setting('SMTP_USER');
    message['To'] = `to;
    message['Subject'] = subject;
    message.set_content(body);
    try {
        port = int(setting('SMTP_PORT', '587'));
        if (port == 465) {
            client = smtplib.SMTP_SSL(
                host, port, timeout=timeout, context=ssl.create_default_context()
            );
        } else {
            client = smtplib.SMTP(host, port, timeout=timeout);
            if (host not in LOOPBACK) {
                client.starttls(context=ssl.create_default_context());
            }
        }
        with client {
            client.login(setting('SMTP_USER'), setting('SMTP_PASSWORD'));
            client.send_message(message);
        }
    } except smtplib.SMTPAuthenticationError {
        raise ChannelError(
            'Email login was rejected; check SMTP_USER and SMTP_PASSWORD.'
        ) from None;
    } except Exception as err {
        raise ChannelError(f'Email delivery failed: {type(err).__name__}.') from None;
    }
}
def send(channel: any, address: any, title: any, body: any) -> any {
    if (channel != 'email') {
        raise ChannelError('Unknown delivery channel.');
    }
    send_email(address, title, body);
}
