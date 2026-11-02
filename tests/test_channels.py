"""Email sender with the network replaced."""
import unittest
from unittest import mock

from integrations import channels

SETTINGS = {'SMTP_HOST': 'smtp.example.com', 'SMTP_USER': 'bot@example.com', 'SMTP_PASSWORD': 'pw'}


class ChannelTests(unittest.TestCase):
    def test_email_requires_server_settings(self):
        with mock.patch.object(channels, 'credentials', return_value={}):
            self.assertFalse(channels.channel_status()['email'])
            with self.assertRaises(channels.ChannelError):
                channels.send_email('me@example.com', 's', 'b')

    def test_email_sends_with_starttls(self):
        with mock.patch.object(channels, 'credentials', return_value=SETTINGS), \
             mock.patch('smtplib.SMTP') as smtp:
            channels.send_email('me@example.com', 'CartCompass reminder', 'milk')
        client = smtp.return_value
        client.starttls.assert_called_once()
        client.login.assert_called_once_with('bot@example.com', 'pw')
        sent = client.send_message.call_args[0][0]
        self.assertEqual(sent['To'], 'me@example.com')
        self.assertEqual(sent['From'], 'bot@example.com')

    def test_port_465_uses_ssl(self):
        with mock.patch.object(channels, 'credentials', return_value=SETTINGS | {'SMTP_PORT': '465'}), \
             mock.patch('smtplib.SMTP_SSL') as smtp_ssl, mock.patch('smtplib.SMTP') as smtp:
            channels.send_email('me@example.com', 's', 'b')
        smtp_ssl.assert_called_once()
        smtp.assert_not_called()

    def test_only_a_loopback_server_may_skip_tls(self):
        with mock.patch.object(channels, 'credentials', return_value=SETTINGS | {'SMTP_HOST': '127.0.0.1', 'SMTP_PORT': '2525'}), \
             mock.patch('smtplib.SMTP') as smtp:
            channels.send_email('me@example.com', 's', 'b')
        smtp.return_value.starttls.assert_not_called()

    def test_errors_do_not_leak_details(self):
        with mock.patch.object(channels, 'credentials', return_value=SETTINGS), \
             mock.patch('smtplib.SMTP', side_effect=OSError('secret detail')):
            with self.assertRaises(channels.ChannelError) as caught:
                channels.send_email('me@example.com', 's', 'b')
        self.assertNotIn('secret', str(caught.exception))

    def test_address_validation(self):
        self.assertTrue(channels.valid_email('jane.doe@umich.edu'))
        self.assertFalse(channels.valid_email('jane@'))
        self.assertFalse(channels.valid_email('two@@example.com'))


if __name__ == '__main__':
    unittest.main()
