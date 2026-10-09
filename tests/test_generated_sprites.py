import importlib.util
import json
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sprite_audit", ROOT / "tools/audit_generated_sprites.py")
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


class GeneratedSpriteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads(qa.CONTRACT.read_text())

    def test_source_cells_have_complete_review_and_valid_bindings(self):
        result = qa.audit(lambda name: (qa.CONTENT / name).read_bytes(), self.contract)
        self.assertEqual(result["reviewed_cells"], 282)
        self.assertEqual(result["reviewed_ids"], 296)
        self.assertEqual(result["redrawn_cells"], 178)

    def test_boundary_and_alpha_fail_before_review_hash(self):
        cell = next(c for c in self.contract["cells"] if c["file"] == "v3_zombie_dwarf_crisp.png")
        original = Image.open(qa.CONTENT / cell["file"]).convert("RGBA")
        with self.subTest("neighbor-cell bleed"):
            bad = original.copy()
            bad.putpixel((31, 16), (255, 255, 255, 255))
            with self.assertRaisesRegex(ValueError, "margin/baseline"):
                qa.verify_cell(bad, cell)
        with self.subTest("antialiased halo"):
            bad = original.copy()
            bad.putpixel((4, 10), (255, 255, 255, 64))
            with self.assertRaisesRegex(ValueError, "Soft alpha"):
                qa.verify_cell(bad, cell)
        with self.subTest("blank replacement"):
            with self.assertRaisesRegex(ValueError, "Empty sprite"):
                qa.verify_cell(Image.new("RGBA", original.size), cell)

    def test_bad_global_reference_and_sheet_geometry_are_rejected(self):
        config = json.loads((qa.CONTENT / "tile_config.json").read_bytes())
        config["tiles-new"][-1]["tiles"][0]["fg"] = 10**9
        with self.assertRaisesRegex(ValueError, "Invalid sprite reference"):
            qa.inspect_config(config, lambda name: (qa.CONTENT / name).read_bytes())
        config["tiles-new"][-1]["sprite_width"] = 31
        with self.assertRaisesRegex(ValueError, "Invalid sheet geometry"):
            qa.inspect_config(config, lambda name: (qa.CONTENT / name).read_bytes())

    def test_weighted_and_directional_reference_forms(self):
        value = [1, {"weight": 20, "sprite": [2, 3]}, {"weight": 7, "sprite": -1}]
        self.assertEqual(list(qa.sprite_refs(value)), [1, 2, 3, -1])


if __name__ == "__main__":
    unittest.main()
