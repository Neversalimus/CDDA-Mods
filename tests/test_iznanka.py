"""Payload and packaging contracts; gameplay is checked by exact-source cata_test."""
import json
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'mods/iznanka/content'

class IznankaPayloadTest(unittest.TestCase):
    def test_every_visible_entity_has_a_sprite(self):
        rows = [r for p in CONTENT.glob('*.json') for r in json.loads(p.read_text(encoding='utf-8'))]
        visible = {r['id'] for r in rows if r['type'] in ('MONSTER', 'ITEM', 'terrain', 'furniture')}
        config = next(r for r in rows if r['type'] == 'mod_tileset')
        sheet = config['tiles-new'][0]
        image = Image.open(CONTENT / sheet['file'])
        self.assertEqual(image.size, (128, 160))
        self.assertEqual(image.mode, 'RGBA')
        mappings = {r['id']: r['fg'] for r in sheet['tiles']}
        self.assertEqual(set(mappings), visible)
        self.assertEqual(len(set(mappings.values())), len(visible))
        for ident, index in mappings.items():
            cell = image.crop(((index % 4) * 32, (index // 4) * 32, (index % 4 + 1) * 32, (index // 4 + 1) * 32))
            self.assertIsNotNone(cell.getbbox(), ident)

    def test_fixed_expedition_is_connected_and_materials_guaranteed(self):
        rows = json.loads((CONTENT / 'mapgen.json').read_text(encoding='utf-8'))
        for row in rows:
            grid = row['object']['rows']
            self.assertEqual(len(grid), 24)
            self.assertTrue(all(len(line) == 24 for line in grid))
        cache = next(r['object'] for r in rows if r['om_terrain'] == 'izn_cache')
        materials = {i['item']: i['amount'] for i in cache['place_item']}
        self.assertGreaterEqual(materials['izn_glassbone'], 2)
        self.assertGreaterEqual(materials['izn_thread'], 2)
        special = next(r for r in json.loads((CONTENT / 'overmap.json').read_text(encoding='utf-8')) if r.get('id') == 'izn_expedition')
        self.assertFalse(special['rotate'])
        coords = {tuple(r['point']) for r in special['overmaps']}
        reached = {next(iter(coords))}
        while True:
            expanded = reached | {p for p in coords if any(abs(p[0]-q[0])+abs(p[1]-q[1])+abs(p[2]-q[2]) == 1 for q in reached)}
            if expanded == reached:
                break
            reached = expanded
        self.assertEqual(reached, coords)

if __name__ == '__main__':
    unittest.main()
