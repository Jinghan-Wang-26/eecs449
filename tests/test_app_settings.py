import unittest
from app_settings import elapsed_hours, instant, later

SETTINGS = {"timezone": "America/Detroit"}


class InstantTests(unittest.TestCase):
    def test_repeated_dst_hour_compares_by_real_time(self):
        # 05:45Z is 01:45 EDT; 06:15Z is 01:15 EST, thirty minutes later.
        first, second = instant("2026-11-01T05:45:00+00:00", SETTINGS), instant("2026-11-01T06:15:00+00:00", SETTINGS)
        self.assertLess(first, second)
        self.assertEqual((second - first).total_seconds(), 1800)
        self.assertEqual((first.hour, first.minute, second.hour, second.minute), (1, 45, 1, 15))
        self.assertEqual(elapsed_hours(first.isoformat(), second.isoformat(), SETTINGS), 0.5)

    def test_local_wall_clock_and_offset_are_kept(self):
        self.assertEqual(instant("2026-07-01T12:00", SETTINGS).isoformat(), "2026-07-01T12:00:00-04:00")
        self.assertEqual(instant("2026-12-01T12:00", SETTINGS).isoformat(), "2026-12-01T12:00:00-05:00")
        self.assertEqual(instant("2026-12-01T17:00:00+00:00", SETTINGS).isoformat(), "2026-12-01T12:00:00-05:00")

    def test_later_adds_real_hours_across_dst_end(self):
        self.assertEqual(later("2026-11-01T00:30", 2, SETTINGS), "2026-11-01T01:30:00-05:00")
