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

    def test_release_check_uses_only_requested_root_mod(self):
        mods, rows = deep.build_suites(TARGET)
        row = next(
            item
            for item in rows
            if item["name"] == "component-aftershock_prime_mom"
        )
        self.assertEqual(
            row["check_mod_ids"],
            ["aftershock_prime_mom_compat"],
        )
        self.assertIn("mindovermatter", row["game_mod_ids"])

    def test_check_mods_interaction_graph_is_identified_for_capability_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            root = data / "mods" / "root"
            dep = data / "mods" / "dependency"
            root.mkdir(parents=True)
            dep.mkdir(parents=True)
            (root / "modinfo.json").write_text(
                '{"type":"MOD_INFO","id":"root_mod","dependencies":["dep_mod"]}',
                encoding="utf-8",
            )
            (dep / "modinfo.json").write_text(
                '{"type":"MOD_INFO","id":"dep_mod","dependencies":[]}',
                encoding="utf-8",
            )
            interactions = dep / "mod_interactions" / "other_mod"
            interactions.mkdir(parents=True)
            (interactions / "override.json").write_text("[]", encoding="utf-8")
            self.assertEqual(
                deep.check_mods_interaction_hazards(data, "root_mod"),
                ["dep_mod"],
            )

    def test_check_mods_plain_graph_has_no_interaction_hazard(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            root = data / "mods" / "plain"
            root.mkdir(parents=True)
            (root / "modinfo.json").write_text(
                '{"type":"MOD_INFO","id":"plain_mod","dependencies":[]}',
                encoding="utf-8",
            )
            self.assertEqual(
                deep.check_mods_interaction_hazards(data, "plain_mod"),
                [],
            )
    def test_check_mods_capability_probe_is_self_contained(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            paths = deep._write_check_mods_interaction_probe(data)
            self.assertEqual(len(paths), 2)
            root = data / "mods" / "__cdda_mods_probe_interaction_root"
            dep = data / "mods" / "__cdda_mods_probe_interaction_dep"
            root_info = deep.suite.read(root / "modinfo.json")
            self.assertIn(
                deep.CHECK_MODS_INTERACTION_PROBE_DEP,
                root_info["dependencies"],
            )
            sentinel = (
                dep
                / "mod_interactions"
                / "cdda_mods_probe_never_loaded"
                / "sentinel.json"
            )
            sentinel_doc = deep.suite.read(sentinel)
            self.assertEqual(sentinel_doc["type"], "snippet")
            self.assertIn(
                deep.CHECK_MODS_INTERACTION_PROBE_TOKEN,
                sentinel_doc["text"],
            )

    def test_cata_test_style_only_exit_is_normalized_but_catch_failure_is_not(self):
        style_line = (
            "12:00 ERROR : src/text_style_check_reader.cpp:63 "
            "[operator ()] (json-error)\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            log_dir = Path(tmp)
            (log_dir / "stderr.log").write_text(style_line, encoding="utf-8")
            (log_dir / "stdout.log").write_text(
                "test cases: 1 | 1 passed\nassertions: - none -\n",
                encoding="utf-8",
            )
            result = deep.normalize_cata_test_result(
                {"exit_code": 1, "errors": [style_line.strip()]},
                log_dir,
            )
            self.assertEqual(result["exit_code"], 0)
            self.assertTrue(result["style_only_exit"])

            (log_dir / "stdout.log").write_text(
                "All tests passed (125 assertions in 4 test cases)\n",
                encoding="utf-8",
            )
            result = deep.normalize_cata_test_result(
                {"exit_code": 1, "errors": [style_line.strip()]},
                log_dir,
            )
            self.assertEqual(result["exit_code"], 0)
            self.assertTrue(result["catch_passed"])

            (log_dir / "stdout.log").write_text(
                "test cases: 4 | 3 passed | 1 failed\n",
                encoding="utf-8",
            )
            result = deep.normalize_cata_test_result(
                {"exit_code": 1, "errors": [style_line.strip()]},
                log_dir,
            )
            self.assertEqual(result["exit_code"], 1)
            self.assertTrue(result["catch_failed"])

    def test_text_style_errors_are_advisory_but_loader_errors_are_fatal(self):
        style, fatal = deep.classify_debug_errors(
            "12:00 ERROR : x/text_style_check_reader.cpp:63 [operator ()] (json-error)\n"
            "12:00 ERROR : (error message will follow backtrace)\n"
            "12:00 ERROR : x/translation.cpp:280 [deserialize] (json-error)\n"
        )
        self.assertEqual(len(style), 1)
        self.assertEqual(len(fatal), 1)
        self.assertIn("translation.cpp:280", fatal[0])

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
