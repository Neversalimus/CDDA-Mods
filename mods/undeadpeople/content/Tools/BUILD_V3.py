#!/usr/bin/env python3
"""Build v3 from v2 and the pinned donor directories in plan.json.
Usage: python BUILD_V3.py BASE_V2 PLAN_JSON OUTPUT_DIR
Requires Python 3.10+ and Pillow. All image files are copied without modification.
"""
import json,copy,shutil,sys,hashlib,bisect
from pathlib import Path
from PIL import Image

def ids(e):return e['id'] if isinstance(e['id'],list) else [e['id']]
def refs(v):
 if isinstance(v,bool):return []
 if isinstance(v,int):return [v]
 if isinstance(v,list):return [x for a in v for x in refs(a)]
 if isinstance(v,dict):return refs(v.get('sprite',[]))
 return []
def allrefs(obj):
 if isinstance(obj,list):return [x for a in obj for x in allrefs(a)]
 if isinstance(obj,dict):return [x for k,v in obj.items() for x in (refs(v) if k in ('fg','bg') else allrefs(v))]
 return []
def transform_spec(v,fn):
 if isinstance(v,bool):return v
 if isinstance(v,int):return fn(v) if v>=0 else v
 if isinstance(v,list):return [transform_spec(a,fn) for a in v]
 if isinstance(v,dict):return {k:transform_spec(a,fn) if k=='sprite' else copy.deepcopy(a) for k,a in v.items()}
 return copy.deepcopy(v)
def transform(obj,fn):
 if isinstance(obj,list):return [transform(a,fn) for a in obj]
 if isinstance(obj,dict):return {k:transform_spec(v,fn) if k in ('fg','bg') else transform(v,fn) for k,v in obj.items()}
 return copy.deepcopy(obj)
def capacity(root,b,info):
 with Image.open(root/b['file']) as im:
  w=b.get('sprite_width',info['width']);h=b.get('sprite_height',info['height'])
  assert w>0 and h>0 and im.width>=w and im.height>=h
  # Match tileset_loader.cpp: incomplete trailing rows/columns are ignored.
  return im.width//w*(im.height//h)
def index(cfg):
 out={}
 for b in cfg['tiles-new']:
  for e in b.get('tiles',[]):
   for i in ids(e):
    assert i not in out,('duplicate',i);out[i]=(b,e)
    for sub in e.get('additional_tiles',[]):
     q=i+'_'+sub['id'];assert q not in out,('duplicate subtile',q);out[q]=(b,sub)
 return out

def build(base_root,planpath,out_root):
 base_root,out_root=Path(base_root),Path(out_root);plan=json.load(open(planpath))
 assert not out_root.exists(),'Use a fresh output directory'
 shutil.copytree(base_root,out_root,ignore=shutil.ignore_patterns('Audit','Tools','__pycache__','SHA256SUMS.json','README_RU.txt','BUILD_VALIDATION.json'))
 cfg=json.load(open(base_root/'tile_config.json'));base=copy.deepcopy(cfg);idx=index(cfg)
 fallback=[b for b in cfg['tiles-new'] if 'ascii' in b];blocks=[b for b in cfg['tiles-new'] if 'ascii' not in b]
 assert cfg['tiles-new']==blocks+fallback
 offset=sum(capacity(base_root,b,cfg['tile_info'][0]) for b in blocks);imports=[];donorinfo=[]
 for d in plan['donors']:
  if not d['ids']:continue
  root=Path(d['root']);dc=json.load(open(root/'tile_config.json'));info=dc['tile_info'][0];assert not info.get('iso')
  wanted=set(d['ids']);entries=[];intervals=[];end=0;selected=set()
  for n,b in enumerate(dc['tiles-new']):
   cap=capacity(root,b,info);intervals.append((end,end+cap,n));end+=cap
   if 'ascii' in b:continue
   for e in b.get('tiles',[]):
    keep=list(dict.fromkeys(i for i in ids(e) if i in wanted and i not in selected))
    if keep:entries.append((n,e,keep));selected.update(keep)
  assert {i for n,e,keep in entries for i in keep}==wanted
  starts=[x[0] for x in intervals]
  def owner(ref):
   n=bisect.bisect_right(starts,ref)-1;assert n>=0 and ref<intervals[n][1];assert 'ascii' not in dc['tiles-new'][n];return n
  used={n for n,e,keep in entries}
  for n,e,keep in entries:used.update(owner(r) for r in allrefs(e) if r>=0)
  newblocks={};newstarts={};scale=cfg['tile_info'][0]['width']/info['width']
  for n in sorted(used):
   b=dc['tiles-new'][n];nb=copy.deepcopy(b);nb['file']='v3_'+d['key']+'_'+Path(b['file']).name;nb['tiles']=[]
   nb['sprite_width']=b.get('sprite_width',info['width']);nb['sprite_height']=b.get('sprite_height',info['height'])
   nb['pixelscale']=b.get('pixelscale',1)*scale
   for key in ['sprite_offset_x','sprite_offset_y','sprite_offset_x_retracted','sprite_offset_y_retracted']:
    if key in b:
     value=b[key]*scale;assert value==int(value);nb[key]=int(value)
   nb['//']='Hybrid v3: '+d['key']+'; artwork copied byte-for-byte; global sprite references remapped'
   shutil.copy2(root/b['file'],out_root/nb['file']);newblocks[n]=nb;newstarts[n]=offset;offset+=intervals[n][1]-intervals[n][0]
   blocks.append(nb)
  def remap(r):
   n=owner(r);return newstarts[n]+r-intervals[n][0]
  for n,e,keep in entries:
   ne=transform(e,remap);ne['id']=keep if isinstance(e['id'],list) else keep[0]
   newblocks[n]['tiles'].append(ne)
   for i in keep:
    generated=[i]+[i+'_'+s['id'] for s in ne.get('additional_tiles',[])];assert not any(q in idx for q in generated),(d['key'],i,[q for q in generated if q in idx])
    idx[i]=(newblocks[n],ne)
    for sub in ne.get('additional_tiles',[]):idx[i+'_'+sub['id']]=(newblocks[n],sub)
   imports+=keep
  donorinfo.append({'key':d['key'],'ids':len(wanted),'sheets':len(used),'native_tile_width':info['width'],'display_scale':scale})
 cfg['tiles-new']=blocks+fallback
 for a in plan['aliases']:
  target,source=a['target'],a['source'];assert target not in idx and source in idx,(target,source)
  block,entry=idx[source];ne=copy.deepcopy(entry);ne['id']=target;ne['//']='Hybrid v3: '+a['reason']+'; source '+source
  block['tiles'].append(ne);idx[target]=(block,ne)
  for sub in ne.get('additional_tiles',[]):
   q=target+'_'+sub['id'];assert q not in idx;idx[q]=(block,sub)
 (out_root/'tile_config.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2)+'\n')
 (out_root/'tileset.txt').write_text('NAME: UndeadPeople_0J_Hybrid_v3\nVIEW: UndeadPeople Hybrid v3 (2026-09-23)\nJSON: tile_config.json\nTILESET: normal_items.png\nLAYERING: layering.json\n')
 final=index(cfg);old=index(base);bad=[r for b in blocks for r in allrefs(b.get('tiles',[])) if r<0 or r>=offset];assert not bad
 for i,(b,e) in old.items():
  nb,ne=final[i];assert e==ne,i
  assert {k:v for k,v in b.items() if k not in ('tiles','//')}=={k:v for k,v in nb.items() if k not in ('tiles','//')},i
 for b in base['tiles-new']:assert (base_root/b['file']).read_bytes()==(out_root/b['file']).read_bytes()
 assert (base_root/'layering.json').read_bytes()==(out_root/'layering.json').read_bytes()
 result={'donors':donorinfo,'imported_top_ids':len(imports),'aliases':len(plan['aliases']),'runtime_ids':len(final),'base_runtime_ids_preserved':len(old),'new_runtime_ids':len(final)-len(old),'sprite_capacity_without_ascii':offset,'duplicate_ids':0,'invalid_references':0,'original_atlases_unchanged':True}
 (out_root/'BUILD_VALIDATION.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':build(*sys.argv[1:4])
