import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HYBRID_TILESET_ID = "UndeadPeople_0J_Hybrid_v3"


class ModTilesetCompatibilityTests(unittest.TestCase):
    def test_all_mod_tilesets_support_hybrid_v3(self):
        mod_tileset_files = sorted((ROOT / "mods").glob("**/mod_tileset.json"))
        self.assertTrue(mod_tileset_files, "No mod_tileset.json files found")

        missing = []
        checked = 0
        for path in mod_tileset_files:
            payload = json.loads(path.read_text(encoding="utf-8"))
            entries = payload if isinstance(payload, list) else [payload]
            for index, entry in enumerate(entries):
                if entry.get("type") != "mod_tileset":
                    continue
                checked += 1
                if HYBRID_TILESET_ID not in entry.get("compatibility", []):
                    missing.append(f"{path.relative_to(ROOT)}[{index}]")

        self.assertGreater(checked, 0, "No mod_tileset definitions found")
        self.assertEqual(
            missing,
            [],
            "Mod tilesets missing Hybrid v3 compatibility: " + ", ".join(missing),
        )


if __name__ == "__main__":
    unittest.main()
