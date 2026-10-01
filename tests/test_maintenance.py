import importlib.util,json,tempfile,unittest,zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('suite',Path(__file__).parents[1]/'tools/modsuite.py')
suite=importlib.util.module_from_spec(spec);spec.loader.exec_module(suite)
class MaintenanceTests(unittest.TestCase):
    def test_archive_reproducible(self):
        with tempfile.TemporaryDirectory() as d:
            a,b=Path(d)/'a.zip',Path(d)/'b.zip'
            suite.make_zip(a,[('b',b'2'),('a',b'1')]);suite.make_zip(b,[('a',b'1'),('b',b'2')])
            self.assertEqual(a.read_bytes(),b.read_bytes())
    def test_safe_path(self):
        with tempfile.TemporaryDirectory() as d:
            for p in ('../x','/x','a/../x','a\\b','C:/x'):
                with self.assertRaises(ValueError):suite.safe_path(Path(d),p)
    def test_tree_hash_tracks_content_and_filename(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'one').write_bytes(b'one');first=suite.tree_hash(p)
            (p/'one').rename(p/'two');self.assertNotEqual(first,suite.tree_hash(p))
    def test_baked_hybrid_contains_secronom_swarmer(self):
        p=suite.ROOT/'mods/undeadpeople/content'
        payload=[('payload/'+f.relative_to(p).as_posix(),f.read_bytes()) for f in suite.files(p)]
        baked=dict(suite.bake_undeadpeople_secronom(payload))
        self.assertIn('payload/compat_secronom_normal.png',baked)
        self.assertIn('payload/compat_secronom_normal_offset.png',baked)
        self.assertIn('payload/compat_secronom_large.png',baked)
        self.assertIn('Secronom baked',baked['payload/tileset.txt'].decode('utf-8'))
        cfg=json.loads(baked['payload/tile_config.json'].decode('utf-8'))
        matches=[]
        for part in cfg['tiles-new']:
            for tile in part.get('tiles',[]):
                ids=tile['id'] if isinstance(tile['id'],list) else [tile['id']]
                if 'mon_zombie_swarmer_weak' in ids:matches.append((part['file'],tile))
        self.assertEqual(len(matches),1)
        self.assertEqual(matches[0][0],'compat_secronom_normal.png')
        self.assertTrue(matches[0][1].get('fg'))

    def test_current_sources(self):
        mods,targets=suite.validate()
        for id,m in mods.items():
            if m['kind']=='native':
                self.assertEqual(suite.read(suite.ROOT/'mods'/id/'native/mod.json')['version'],m['variants'][-1]['version'])
        self.assertNotIn('ncmm',mods)
if __name__=='__main__':unittest.main()
