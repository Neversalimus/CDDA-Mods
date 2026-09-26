#!/usr/bin/env python3
"""Fetch only pinned public donor snapshots, verify SHA256, retain their native layout."""
import json,hashlib,urllib.request,zipfile,io
from pathlib import Path
sources=json.load(open(Path(__file__).with_name('SOURCES.json')))
def get(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Hybrid-v3-rebuild'}),timeout=120) as r:return r.read()
def verified(data,sha):
 assert hashlib.sha256(data).hexdigest()==sha,'Source hash mismatch';return data
for d in sources['donors']:
 root=Path(d['root']);root.mkdir(parents=True,exist_ok=True)
 if d['kind']=='release_zip':
  blob=verified(get(d['zip_url']),d['zip_sha256'])
  with zipfile.ZipFile(io.BytesIO(blob)) as z:
   prefix=d['zip_directory']+'/'
   for n in [d['config_file']]+[f['name'] for f in d['files']]:(root/n).write_bytes(z.read(prefix+n))
 else:
  (root/d['config_file']).write_bytes(verified(get(d['url_base']+d['config_file']),d['config_sha256']))
  for f in d['files']:(root/f['name']).write_bytes(verified(get(d['url_base']+f['name']),f['sha256']))
 for f in d['files']:verified((root/f['name']).read_bytes(),f['sha256'])
 verified((root/d['config_file']).read_bytes(),d['config_sha256'])
 if d['kind']=='mod_tileset':
  original=json.load(open(root/d['config_file']))[0]
  (root/'tile_config.json').write_text(json.dumps({'tile_info':[{'width':32,'height':32,'pixelscale':1}],'tiles-new':original['tiles-new']}))
 print('Verified',d['key'],d['revision'])
