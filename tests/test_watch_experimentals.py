import unittest
from datetime import timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import watch_experimentals as watch


class ExperimentalWatchTests(unittest.TestCase):
    def test_tag_time_orders_builds_chronologically(self):
        old = watch.tag_time("cdda-experimental-2026-10-01-1040")
        new = watch.tag_time("cdda-experimental-2026-10-01-1124")
        self.assertIsNotNone(old)
        self.assertIsNotNone(new)
        self.assertLess(old, new)
        self.assertEqual(new.tzinfo, timezone.utc)

    def test_discovery_skips_known_and_already_attempted(self):
        known = {
            "cdda-experimental-2026-10-01-1040": {"channel": "experimental"}
        }
        releases = [
            {
                "tag_name": "cdda-experimental-2026-10-01-1124",
                "draft": False,
            },
            {
                "tag_name": "cdda-experimental-2026-10-01-1200",
                "draft": False,
            },
            {
                "tag_name": "cdda-experimental-2026-10-01-0956",
                "draft": False,
            },
        ]
        seen = {
            "CDDA Mods certify / cdda-experimental-2026-10-01-1124"
        }
        found = watch.discover_candidates(releases, known, seen)
        self.assertEqual(
            [row["tag_name"] for row in found],
            ["cdda-experimental-2026-10-01-1200"],
        )


if __name__ == "__main__":
    unittest.main()
