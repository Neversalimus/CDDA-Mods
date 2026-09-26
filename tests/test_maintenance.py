import importlib.util,tempfile,unittest,zipfile
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
    def test_current_sources(self):
        mods,targets=suite.validate()
        for id,m in mods.items():
            if m['kind']=='native':
                self.assertEqual(suite.read(suite.ROOT/'mods'/id/'native/mod.json')['version'],m['variants'][-1]['version'])
        self.assertNotIn('ncmm',mods)
if __name__=='__main__':unittest.main()
