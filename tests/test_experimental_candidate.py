import json
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import experimental_candidate as candidate


class ExperimentalCandidateTests(unittest.TestCase):
    def test_candidate_extends_only_latest_experimental_variant(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "catalog" / "targets").mkdir(parents=True)
            mod = root / "mods" / "sample"
            mod.mkdir(parents=True)
            manifest = {
                "schema": 1,
                "id": "sample",
                "variants": [
                    {
                        "id": "old",
                        "targets": ["experimental-2026-09-01-0001"],
                    },
                    {
                        "id": "current",
                        "targets": ["experimental-2026-09-23-0546"],
                    },
                ],
            }
            (mod / "manifest.json").write_text(
                json.dumps(manifest),
                encoding="utf-8",
            )

            report = candidate.prepare_candidate(
                root,
                "cdda-experimental-2026-10-01-1124",
                "a" * 40,
            )
            self.assertEqual(
                report["target"],
                "experimental-2026-10-01-1124",
            )
            updated = json.loads(
                (mod / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertNotIn(
                "experimental-2026-10-01-1124",
                updated["variants"][0]["targets"],
            )
            self.assertIn(
                "experimental-2026-10-01-1124",
                updated["variants"][1]["targets"],
            )

            second = candidate.prepare_candidate(
                root,
                "cdda-experimental-2026-10-01-1124",
                "a" * 40,
            )
            self.assertEqual(second["changed_manifests"], [])


if __name__ == "__main__":
    unittest.main()
