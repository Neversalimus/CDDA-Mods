import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "deep_summary",
    Path(__file__).parents[1] / "tools" / "deep_summary.py",
)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class DeepSummaryTests(unittest.TestCase):
    def test_warning_fingerprint_is_order_independent(self):
        a = summary.warning_fingerprint({"b", "a"})
        b = summary.warning_fingerprint({"a", "b"})
        self.assertEqual(a, b)
        self.assertEqual(a["count"], 2)

    def test_baseline_comparison_is_informational(self):
        observed = {"suite": summary.warning_fingerprint({"one", "two"})}
        baseline = {
            "suites": {
                "suite": {
                    "count": 1,
                    "sha256": summary.warning_fingerprint({"one"})["sha256"],
                }
            }
        }
        result = summary.compare_baseline(observed, baseline)
        self.assertEqual(result["suite"]["state"], "warning-count-increased")

    def test_source_report_rows_keep_authoritative_failure(self):
        rows = []
        warnings = {}
        summary.scan_report(
            Path("artifact/report.json"),
            {
                "kind": "source-cata-test",
                "runs": [
                    {
                        "suite": "component-demo",
                        "spec": "[force_load_game]",
                        "result": {
                            "exit_code": 1,
                            "errors": ["boom"],
                            "style_warnings": ["warning"],
                            "duration_seconds": 1.25,
                        },
                    }
                ],
            },
            rows,
            warnings,
        )
        self.assertEqual(rows[0]["status"], "FAIL")
        self.assertEqual(rows[0]["duration_seconds"], 1.25)
        self.assertEqual(warnings["component-demo"], {"warning"})


if __name__ == "__main__":
    unittest.main()
