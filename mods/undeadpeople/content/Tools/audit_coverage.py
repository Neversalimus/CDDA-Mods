#!/usr/bin/env python3
"""Static CDDA tileset coverage audit. Usage: python audit_coverage.py SOURCE_ROOT TILESET_ROOT OUTPUT_ROOT"""
import json,sys,copy,csv,collections
from pathlib import Path
src,tiles,out=map(Path,sys.argv[1:]);out.mkdir(exist_ok=True,parents=True)
mods=['dda','no_npc_food','personal_portal_storms','magiclysm','mindovermatter','xedra_evolved','package_bionic_professions','perk_melee_system','extra_mut_scens','MMA','bombastic_perks']
catmap={'ITEM':'item','MONSTER':'monster','terrain':'terrain','furniture':'furniture','vehicle_part':'vehicle','overmap_terrain':'overmap','field_type':'field','trap':'trap'}
roots={'dda':src/'data/json'}
for p in (src/'data/mods').glob('*/modinfo.json'):
 for o in json.loads(p.read_text()):
  if o.get('id') in mods and o['id']!='dda':roots[o['id']]=p.parent
cfg=json.loads((tiles/'tile_config.json').read_text());sprite_ids={};extra_ids={}
for block in cfg['tiles-new']:
 for e in block.get('tiles',[]):
  ids=e['id'] if isinstance(e['id'],list) else [e['id']]
  for i in ids:
   sprite_ids[i]=block['file']
   for sub in e.get('additional_tiles',[]):extra_ids[i+'_'+sub['id']]=block['file']
# additional_tiles are runtime IDs, but top-level entries take precedence only according to load order.
sprite_ids.update({k:v for k,v in extra_ids.items() if k not in sprite_ids})
real={c:{} for c in catmap.values()};abstract={c:{} for c in catmap.values()};unresolved=[];parseerrors=[];modtiles=[]
stages=[(mod,False) for mod in mods]+[(mod,True) for mod in mods]
for mod,interaction_stage in stages:
 pending=[]
 for p in sorted(roots[mod].rglob('*.json')):
  parts=p.relative_to(roots[mod]).parts
  is_interaction='mod_interactions' in parts
  if is_interaction != interaction_stage:continue
  if is_interaction and parts[parts.index('mod_interactions')+1] not in mods:continue
  try:objs=json.loads(p.read_text())
  except Exception as e:parseerrors.append([str(p),str(e)]);continue
  for o in objs if isinstance(objs,list) else [objs]:
   if not isinstance(o,dict):continue
   if o.get('type')=='mod_tileset':modtiles.append(str(p))
   if o.get('type') not in catmap:continue
   c=catmap[o['type']];ids=o.get('id',o.get('abstract'))
   if not ids:continue
   for i in ids if isinstance(ids,list) else [ids]:pending.append((c,i,o,str(p.relative_to(src)),mod))
 while pending:
  later=[];count=0
  for c,i,o,p,mod in pending:
   parent=o.get('copy-from');base={};isabs='abstract' in o
   if parent:
    base=real[c].get(parent,abstract[c].get(parent))
    if base is None:later.append((c,i,o,p,mod));continue
   elif i in real[c]:base=real[c][i]
   result=copy.deepcopy(base);ll=result.get('_ll',[]);ll=list(ll)
   if parent:
    if c in ('terrain','furniture'):ll=[parent]
    elif c in ('monster','field') and not ll:ll=[parent]
    elif c=='item' and parent in real[c]:ll=[parent]
    elif c=='overmap':ll=[parent]+ll
    elif c=='vehicle':
     ll=[parent]
     for _ in range(5):
      if ll[0] in real[c]:break
      a=abstract[c].get(ll[0]);nxt=a.get('_ll',[]) if a else []
      if not nxt:break
      ll=nxt[:1]
   if 'looks_like' in o:ll=o['looks_like'] if isinstance(o['looks_like'],list) else [o['looks_like']]
   for k,v in o.items():
    if k not in ('extend','delete','relative','proportional'):result[k]=copy.deepcopy(v)
   for k,v in o.get('extend',{}).items():
    if isinstance(v,list):result[k]=list(result.get(k,[]))+v
   for k,v in o.get('delete',{}).items():
    if isinstance(v,list) and isinstance(result.get(k),list):result[k]=[x for x in result[k] if x not in v]
   result.update(_ll=ll,_id=i,_path=p,_mod=mod,_origin=base.get('_origin',mod) if (i==parent or i in real[c]) else mod)
   (abstract[c] if isabs else real[c])[i]=result;count+=1
  if not count:unresolved.extend([(c,i,p,parent) for c,i,o,p,m in later for parent in [o.get('copy-from')]]);break
  pending=later

def sprite(i,season):
 if i+'_season_'+season in sprite_ids:return i+'_season_'+season
 return i if i in sprite_ids else None

def lookup(i,c,season='summer',depth=10,trail=(),variant=''):
 if not i or depth<=0:return None
 candidates=[]
 if variant:
  if c=='vehicle':
   chunk=variant
   while chunk:
    candidates.append(i+'_'+chunk);chunk=chunk.rsplit('_',1)[0] if '_' in chunk else ''
  else:candidates.append(i+'_var_'+variant)
 candidates.append(i)
 for q in candidates:
  s=sprite(q,season)
  if s:return [*trail,i,s]
 if c=='trap':return None
 key=i[3:] if c=='vehicle' else i
 obj=real.get(c,{}).get(key)
 if obj is None:return None
 ll=obj.get('_ll',[])
 if c=='vehicle':
  if not ll:return None
  for q,cat in [('vp_'+ll[0],c),(ll[0],c),(ll[0],'furniture')]:
   r=lookup(q,cat,season,depth-1,(*trail,i),variant)
   if r:return r
 else:
  for idx,q in enumerate(ll):
   r=lookup(q,c,season,depth-1-idx,(*trail,i))
   if r:return r
 return None

def name(o):
 n=o.get('name','');return n.get('str',n.get('str_sp','')) if isinstance(n,dict) else n
rows=[]
for c,objects in real.items():
 for i,o in objects.items():
  query='vp_'+i if c=='vehicle' else i
  variants=['']
  # Main table counts base part IDs; variant-only coverage is reported separately.
  if c in ('vehicle','item') and o.get('variants'):
   variants=list(dict.fromkeys([v.get('id','') for v in o['variants'] if isinstance(v,dict)])) or ['']
  if c=='field':variants=[str(x) for x in range(1,len(o.get('intensity_levels',[]))+1)] or ['1']
  results=[]
  for sea in ['spring','summer','autumn','winter']:
   for v in variants:
    r=None
    if c=='field':r=lookup(query+'_int'+v,c,sea)
    if not r:r=lookup(query,c,sea,variant=v if c in ('vehicle','item') else '')
    results.append(r)
  ok=sum(bool(r) for r in results)
  status='missing' if not ok else ('partial' if ok<len(results) else 'covered')
  direct=all(r and len(r)==2 for r in results)
  route='direct' if status=='covered' and direct else 'looks_like' if status=='covered' else status
  r=next((r for r in results if r),None)
  rows.append(dict(category=c,id=i,name=name(o),origin=o['_origin'],last_mod=o['_mod'],status=route,matched=r[-1] if r else '',sheet=sprite_ids.get(r[-1],'') if r else '',looks_like=' | '.join(o['_ll']),source=o['_path'],flags=' | '.join(o.get('flags',[])),chain=' -> '.join(r[:-1]) if r else ''))
rows.sort(key=lambda r:(r['category'],r['origin'],r['id']))
with (out/'coverage_all.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
with (out/'coverage_missing.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(r for r in rows if r['status'] in ('missing','partial'))
summary={}
for grouping in ['category','origin']:
 summary[grouping]={}
 for group in sorted(set(r[grouping] for r in rows)):
  cc=collections.Counter(r['status'] for r in rows if r[grouping]==group);cc['total']=sum(cc.values());summary[grouping][group]=dict(cc)
summary.update(mods=mods,unresolved=unresolved,parse_errors=parseerrors,mod_tilesets=modtiles,top_level_ids=len({i for b in cfg['tiles-new'] for e in b.get('tiles',[]) for i in (e['id'] if isinstance(e['id'],list) else [e['id']])}),runtime_tile_ids=len(sprite_ids))
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
(out/'resolved_objects.json').write_text(json.dumps(real,ensure_ascii=False))
print(json.dumps(summary,ensure_ascii=False,indent=2))
