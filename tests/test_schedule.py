"""Deterministic schedule cases, no model or provider requests."""
import jaclang
import unittest
from planning.schedule import weekly_hours, schedule_visit
from tests.test_visits import TRAVEL, STORE, NOW


class ScheduleTests(unittest.TestCase):
    def schedule(self, windows, hours='', now=NOW, zone='America/New_York', **store):
        return schedule_visit(windows, TRAVEL, dict(STORE, opening_hours=hours, **store), now, zone)

    def test_regular_hours_shift_departure_until_store_opens(self):
        result = self.schedule(['SAT 07:00-12:00'], 'Mo-Su 09:00-22:00')
        self.assertEqual(result['departure_at'], '2030-01-05T08:55-05:00')
        self.assertEqual(result['arrival_at'], '2030-01-05T09:00-05:00')
        self.assertEqual(result['leave_store_at'], '2030-01-05T09:20-05:00')
        self.assertEqual(result['return_at'], '2030-01-05T09:25-05:00')
        self.assertEqual(result['hours_status'], 'REGULAR_HOURS_FIT')

    def test_closing_before_shopping_finishes_blocks(self):
        result = self.schedule(['SAT 21:50-23:00'], 'Mo-Su 09:00-22:00')
        self.assertEqual(result['hours_status'], 'NO_OPEN_SLOT')
        self.assertTrue(result['blocker'])
        self.assertFalse(result['departure_at'])

    def test_unknown_holiday_and_overnight_syntax_are_not_guessed(self):
        for hours in ('', 'Mo-Su 09:00-22:00; PH off', 'Fr 20:00-02:00', 'Mo 25:00-26:00', 'Mo 08:00-20:00; Mo off'):
            with self.subTest(hours=hours):
                result = self.schedule(['SAT 14:00-17:00'], hours)
                self.assertEqual(result['hours_status'], 'UNKNOWN')
                self.assertFalse(result['blocker'])
        self.assertIsNone(weekly_hours('Mo-Su sunrise-sunset'))

    def test_closed_day_and_split_hours(self):
        self.assertTrue(self.schedule(['SUN 14:00-17:00'], 'Mo-Sa 08:00-20:00; Su off')['blocker'])
        result = self.schedule(['SAT 12:00-15:00'], 'Sa 08:00-12:00,14:00-20:00')
        self.assertEqual(result['arrival_at'], '2030-01-05T14:00-05:00')
        self.assertEqual(self.schedule(['SAT 14:00-17:00'], '24/7')['hours_status'], 'REGULAR_HOURS_FIT')

    def test_past_windows_advance_and_unsorted_windows_choose_earliest(self):
        result = self.schedule(['SAT 14:00-17:00', 'TUE 09:00-12:00'])
        self.assertEqual(result['departure_at'], '2030-01-01T10:05-05:00')
        result = self.schedule(['TUE 08:00-09:00'])
        self.assertEqual(result['departure_at'], '2030-01-08T08:00-05:00')

    def test_address_timezone_overrides_server_timezone(self):
        result = self.schedule(['TUE 08:00-09:00'], zone='America/Los_Angeles')
        self.assertEqual(result['departure_at'], '2030-01-01T08:00-08:00')
        self.assertEqual(result['timezone'], 'America/Los_Angeles')
        self.assertEqual(self.schedule(['TUE 08:00-09:00'], zone='bad/zone')['timezone'], 'America/New_York')
        self.assertTrue(self.schedule(['TUE 08:00-09:00'], zone='')['timezone_notice'])

    def test_store_timezone_is_used_for_opening_hours(self):
        result = self.schedule(['SAT 14:00-17:00'], 'Sa 14:00-18:00', timezone='America/Chicago')
        self.assertEqual(result['arrival_at'], '2030-01-05T14:00-06:00')
        self.assertEqual(result['departure_at'], '2030-01-05T14:55-05:00')

    def test_dst_gap_and_ambiguous_windows_are_not_guessed(self):
        for now, window, expected in [('2030-03-09T10:00:00-05:00', 'SUN 02:15-04:00', ''),
                                       ('2030-11-02T10:00:00-04:00', 'SUN 01:15-03:00', '')]:
            result = self.schedule([window], now=now)
            self.assertEqual(result['departure_at'], expected)
            self.assertTrue(result['blocker'])
        result = self.schedule(['SUN 03:00-04:00'], now='2030-03-09T10:00:00-05:00')
        self.assertEqual(result['departure_at'], '2030-03-10T03:00-04:00')
