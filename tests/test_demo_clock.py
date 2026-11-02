import copy
import unittest
from app_settings import instant
from providers.demo_clock import rebase_fixture


class DemoClockTests(unittest.TestCase):
    def fixture(self):
        return {"observed_at": "2026-10-10T08:00", "valid_until": "2026-10-17T08:00", "offers": [{},
                {"observed_at": "2026-10-01T08:00", "valid_until": "2026-10-02T08:00"}]}

    def test_future_dates_keep_age_ttl_and_stale_override(self):
        for now in ("2026-10-22T10:00", "2030-01-01T11:00", "2027-03-14T10:00", "2027-11-07T10:00"):
            with self.subTest(now=now):
                fresh, stale = rebase_fixture(self.fixture(), now)["offers"]
                self.assertLessEqual(instant(fresh["observed_at"]), instant(now))
                self.assertGreater(instant(fresh["valid_until"]), instant(now))
                self.assertLess(instant(stale["valid_until"]), instant(now))

    def test_dst_change_day_anchors_at_local_midnight(self):
        fresh, _ = rebase_fixture(self.fixture(), "2026-11-01T10:00")["offers"]
        self.assertEqual(fresh["observed_at"], instant("2026-11-01T00:00").isoformat(timespec="seconds"))

    def test_same_day_refresh_is_stable(self):
        self.assertEqual(rebase_fixture(self.fixture(), "2028-01-01T08:00"), rebase_fixture(self.fixture(), "2028-01-01T20:00"))

    def test_raw_fixture_mode_keeps_historical_timestamps(self):
        original = self.fixture()
        self.assertEqual(rebase_fixture(copy.deepcopy(original)), original)
