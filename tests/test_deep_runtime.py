import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import deep_cdda_runtime as deep
import fetch_cdda_release as fetch


TARGET = "experimental-2026-09-23-0546"


class DeepRuntimePlanTests(unittest.TestCase):
    def test_every_json_component_is_covered_and_combined(self):
        mods, rows = deep.build_suites(TARGET)
        covered = {
            component
            for row in rows
            for component in row["components"]
        }
        self.assertEqual(set(mods), covered)
        combined = next(
            row for row in rows if row["name"] == "combined-all-json"
        )
        self.assertEqual(set(combined["components"]), set(mods))
        self.assertEqual(combined["game_mod_ids"][0], "dda")
        self.assertTrue(combined["content_sha256"])

    def test_dependency_closure_keeps_secronom_before_expansion(self):
        mods = deep.json_components(TARGET)
        order = deep.closure(mods, ["secronom_plus"])
        self.assertEqual(order[-2:], ["secronom", "secronom_plus"])

    def test_depths_are_deliberately_separated(self):
        self.assertEqual(
            deep.source_specs("load", combined=False),
            ["[force_load_game]"],
        )
        self.assertIn(
            "~[slow] ~[.],starting_items",
            deep.source_specs("full", combined=False),
        )
        exhaustive = deep.source_specs("exhaustive", combined=True)
        self.assertIn("~[slow] ~[.],starting_items", exhaustive)
        self.assertIn("[slow] ~starting_items", exhaustive)


    def test_axiom_component_gets_exact_engine_lifecycle_probe(self):
        self.assertEqual(
            deep.source_specs(
                "load",
                combined=False,
                suite_name="component-axiom_7",
            ),
            ["[force_load_game]", "[axiom7_lifecycle]"],
        )
        self.assertNotIn(
            "[axiom7_lifecycle]",
            deep.source_specs(
                "full",
                combined=True,
                suite_name="combined-all-json",
            ),
        )

    def test_axiom_runtime_probe_is_wired_into_source_build(self):
        probe = (
            ROOT / "tools" / "runtime_probes" / "axiom7_lifecycle_test.cpp"
        ).read_text(encoding="utf-8")
        workflow = (
            ROOT / ".github" / "workflows" / "deep-runtime.yml"
        ).read_text(encoding="utf-8")
        for required in (
            "[axiom7_lifecycle]",
            "MISSION_AXIOM_SENSOR_RELAY",
            "AXIOM_KX91_SWAP_OPERATIONAL_PLAYER",
            "EOC_AXIOM_SECURITY_ALARM",
            "axiom_kx91_dormant",
        ):
            self.assertIn(required, probe)
        self.assertIn(
            "tools/runtime_probes/axiom7_lifecycle_test.cpp",
            workflow,
        )

    def test_external_game_dependencies_are_explicit_for_runtime(self):
        mods = deep.json_components(TARGET)
        game_ids = deep.game_ids_for(
            mods, ["aftershock_prime_mom"], TARGET
        )
        self.assertIn("mindovermatter", game_ids)
        self.assertLess(
            game_ids.index("mindovermatter"),
            game_ids.index("aftershock_prime_mom_compat"),
        )
        self.assertLess(
            game_ids.index("aftershock_prime"),
            game_ids.index("aftershock_prime_mom_compat"),
        )

    def test_release_asset_prefers_graphical_windows_x64(self):
        assets = [
            {"name": "cdda-linux-terminal-only-x64-foo.tar.gz"},
            {"name": "cdda-windows-with-graphics-and-sounds-x64-foo.zip"},
            {"name": "cdda-windows-with-graphics-x64-foo.zip"},
            {"name": "cdda-windows-with-graphics-x64-symbols.zip"},
        ]
        chosen = fetch.choose_asset(assets)
        self.assertEqual(
            chosen["name"],
            "cdda-windows-with-graphics-x64-foo.zip",
        )

    def test_release_asset_rejects_symbol_archive(self):
        assets = [
            {"name": "cdda-windows-with-graphics-x64-symbols.zip"},
            {"name": "cdda-windows-with-graphics-x64-real.zip"},
        ]
        chosen = fetch.choose_asset(assets)
        self.assertEqual(
            chosen["name"],
            "cdda-windows-with-graphics-x64-real.zip",
        )

    def test_release_zip_blocks_path_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("../escape.txt", "no")
            with self.assertRaises(ValueError):
                fetch.extract_zip_safe(archive, root / "out")
            self.assertFalse((root / "escape.txt").exists())


if __name__ == "__main__":
    unittest.main()
