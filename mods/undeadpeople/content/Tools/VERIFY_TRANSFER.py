#!/usr/bin/env python3
"""Independently compare every imported sprite cell against its pinned donor image."""
import json,sys,hashlib,bisect
from pathlib import Path
from PIL import Image
from BUILD_V3 import allrefs
planpath,finaldir,out=map(Path,sys.argv[1:]);plan=json.load(open(planpath))
def load(root):
 cfg=json.load(open(root/'tile_config.json'));idx={};sheets=[];offset=0
 for b in cfg['tiles-new']:
  with Image.open(root/b['file']) as im:iw,ih=im.size
  w=b.get('sprite_width',cfg['tile_info'][0]['width']);h=b.get('sprite_height',cfg['tile_info'][0]['height']);n=iw//w*(ih//h)
  sheets.append((offset,offset+n,b,w,h,iw));offset+=n
  for e in b.get('tiles',[]):
   for i in e['id'] if isinstance(e['id'],list) else [e['id']]:idx.setdefault(i,(b,e))
 starts=[b[0] for b in sheets];cache={}
 def cell(ref):
  if ref not in cache:
   start,end,b,w,h,iw=sheets[bisect.bisect_right(starts,ref)-1];q=ref-start
   with Image.open(root/b['file']) as im:
    box=im.convert('RGBA').crop((q%(iw//w)*w,q//(iw//w)*h,q%(iw//w)*w+w,q//(iw//w)*h+h))
    cache[ref]=(box.size,hashlib.sha256(box.tobytes()).hexdigest())
  return cache[ref]
 return cfg,idx,cell
final,fi,fc=load(finaldir);count=0;entries=0
for d in plan['donors']:
 if not d['ids']:continue
 dc,di,get=load(Path(d['root']));scale=final['tile_info'][0]['width']/dc['tile_info'][0]['width']
 for i in d['ids']:
  b,e=di[i];nb,ne=fi[i];old=allrefs(e);new=allrefs(ne);assert len(old)==len(new),i
  assert nb.get('pixelscale',1)==b.get('pixelscale',1)*scale,i
  for k in ['sprite_offset_x','sprite_offset_y','sprite_offset_x_retracted','sprite_offset_y_retracted']:
   if k in b:assert nb[k]==b[k]*scale,(i,k)
  for src,dst in zip(old,new):assert get(src)==fc(dst),(d['key'],i,src,dst);count+=1
  entries+=1
for a in plan['aliases']:
 b,e=fi[a['source']];nb,ne=fi[a['target']]
 assert b is nb,a
 assert {k:v for k,v in e.items() if k not in ['id','//']}=={k:v for k,v in ne.items() if k not in ['id','//']},a
result={'imported_entries_verified':entries,'sprite_references_pixel_compared':count,'pixel_mismatches':0,'alias_entries_verified':len(plan['aliases']),'geometry_scale_verified':True}
out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
