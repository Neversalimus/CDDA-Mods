import json
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


    def test_external_game_dependencies_are_explicit_for_cata_test(self):
        mods = deep.json_components(TARGET)
        game_ids = deep.game_ids_for(mods, ["aftershock_prime_mom"], TARGET)
        self.assertIn("mindovermatter", game_ids)
        self.assertLess(game_ids.index("mindovermatter"), game_ids.index("aftershock_prime_mom_compat"))
        self.assertLess(game_ids.index("aftershock_prime"), game_ids.index("aftershock_prime_mom_compat"))


    def test_install_lifecycle_matrix_covers_every_installable_content_component(self):
        matrix = json.loads(
            (ROOT / "tests" / "deep_runtime_matrix.json").read_text(encoding="utf-8")
        )
        manifests = [
            json.loads(p.read_text(encoding="utf-8"))
            for p in sorted((ROOT / "mods").glob("*/manifest.json"))
        ]
        expected = {
            m["id"]
            for m in manifests
            if m["kind"] in {"json", "tileset"}
            and any(
                TARGET in v.get("targets", [])
                and v.get("available", True)
                and v.get("validation") != "blocked"
                for v in m["variants"]
            )
        }
        by_id = {m["id"]: m for m in manifests}

        def package_closure(ids):
            out = set()
            def visit(mid):
                if mid in out:
                    return
                for dep in by_id[mid].get("dependencies", []):
                    visit(dep)
                out.add(mid)
            for mid in ids:
                visit(mid)
            return out

        scenarios = matrix["install_scenarios"]
        covered = set()
        for row in scenarios:
            covered.update(package_closure(row["mods"]))
        self.assertEqual(expected, covered)
        self.assertTrue(all(row["mods"] for row in scenarios))
        all_content = next(row for row in scenarios if row["id"] == "all-content")
        self.assertEqual(expected, package_closure(all_content["mods"]))

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
