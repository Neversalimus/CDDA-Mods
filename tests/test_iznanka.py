"""Payload contracts; gameplay is checked by exact-source cata_test."""
import json
import unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
CONTENT=ROOT/'mods/iznanka/content'

class IznankaPayloadTest(unittest.TestCase):
    def test_every_visible_entity_has_valid_sprite(self):
        rows=[r for p in CONTENT.glob('*.json') for r in json.loads(p.read_text(encoding='utf-8'))]
        visible={r['id'] for r in rows if r['type'] in ('MONSTER','ITEM','terrain','furniture')}
        terrain_ids={r['id'] for r in rows if r['type']=='terrain'}
        config=next(r for r in rows if r['type']=='mod_tileset')
        cells={}
        for sheet in config['tiles-new']:
            im=Image.open(CONTENT/sheet['file'])
            for y in range(0,im.height,32):
                for x in range(0,im.width,32):
                    cells[len(cells)]=im.crop((x,y,x+32,y+32))
        offset=0;covered=set()
        for sheet in config['tiles-new']:
            im=Image.open(CONTENT/sheet['file']);self.assertEqual(im.mode,'RGBA')
            w=sheet['sprite_width'];h=sheet['sprite_height'];self.assertEqual((w,h),(32,32))
            self.assertEqual(im.width%w,0);self.assertEqual(im.height%h,0)
            count=(im.width//w)*(im.height//h)
            for row in sheet['tiles']:
                ids=[row['id']] if isinstance(row['id'],str) else row['id']
                self.assertFalse(covered.intersection(ids));covered.update(ids)
                refs=[row['fg']] if isinstance(row['fg'],int) else [r['sprite'] for r in row['fg']]
                for idx in refs:
                    self.assertTrue(offset<=idx<offset+count)
                    i=idx-offset;x=(i%(im.width//w))*w;y=(i//(im.width//w))*h
                    cell=im.crop((x,y,x+w,y+h));self.assertIsNotNone(cell.getbbox())
                    if set(ids).intersection({'t_izn_ash','t_izn_bog'}):
                        self.assertEqual(cell.getchannel('A').getextrema(),(255,255),'Ground must never expose black cell borders')
                bg=row.get('bg',[])
                bg_refs=[bg] if isinstance(bg,int) else [r['sprite'] for r in bg]
                for idx in bg_refs:
                    self.assertIn(idx,cells)
                    self.assertEqual(cells[idx].getchannel('A').getextrema(),(255,255))
                if set(ids)&terrain_ids and any(cells[idx].getchannel('A').getextrema()!=(255,255) for idx in refs):
                    self.assertTrue(bg_refs,'Transparent terrain needs opaque ground behind it')
            offset+=count
        self.assertEqual(visible,covered)

    def test_authored_maps_and_guaranteed_materials(self):
        rows=[r for filename in ['mapgen.json','town_mapgen.json'] for r in json.loads((CONTENT/filename).read_text(encoding='utf-8'))]
        for row in rows:
            grid=row['object']['rows'];self.assertEqual(len(grid),24)
            self.assertTrue(all(len(line)==24 for line in grid))
            self.assertTrue(set(''.join(grid)) <= set(row['object']['terrain']))
        cache=next(r['object'] for r in rows if r['om_terrain']=='izn_cache')
        materials={i['item']:i['amount'] for i in cache['place_item']}
        self.assertGreaterEqual(materials['izn_glassbone'],2);self.assertGreaterEqual(materials['izn_thread'],2)
        specials=json.loads((CONTENT/'overmap.json').read_text(encoding='utf-8'))
        for id in ['izn_expedition','izn_town']:
            special=next(r for r in specials if r.get('id')==id)
            self.assertFalse(special['rotate'])
            coords={tuple(r['point']) for r in special['overmaps']};reached={next(iter(coords))}
            while True:
                expanded=reached|{p for p in coords if any(sum(abs(a-b) for a,b in zip(p,q))==1 for q in reached)}
                if expanded==reached:break
                reached=expanded
            self.assertEqual(reached,coords)
        radio=next(r['object'] for r in rows if r['om_terrain']=='izn_radio')
        self.assertEqual(sum(m.get('repeat',1) for m in radio['place_monster'] if m['monster']=='mon_izn_voice'),3)

if __name__=='__main__':unittest.main()
