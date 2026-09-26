import sys,runpy,contextlib,io,json,collections,copy
from pathlib import Path
from PIL import Image
sys.path.insert(0,'v2_work/build_tools')
from BUILD_V2 import allrefs,index,capacity
sys.argv=['audit','source','v2_work/UndeadPeople_0J_Hybrid_v2','v3_work/resolver']
with contextlib.redirect_stdout(io.StringIO()):env=runpy.run_path('coverage/audit_coverage.py')
real=env['real'];lookup=env['lookup'];tiles=env['sprite_ids'];cfg=env['cfg'];base_top=index(cfg)
states=[]
for c,objects in real.items():
 for i,o in objects.items():
  vv=['']
  if c in ('vehicle','item') and o.get('variants'):vv=[v.get('id','') for v in o['variants'] if isinstance(v,dict)] or ['']
  if c=='field':vv=[str(v) for v in range(1,len(o.get('intensity_levels',[]))+1)] or ['1']
  states.extend((c,i,s,v) for s in ['spring','summer','autumn','winter'] for v in vv)
def find(st):
 c,i,s,v=st;q='vp_'+i if c=='vehicle' else i
 return (lookup(q+'_int'+v,c,s) or lookup(q,c,s)) if c=='field' else lookup(q,c,s,variant=v)
origins={i:i for i in tiles};baseline={s:origins[find(s)[-1]] for s in states if find(s)};added={}
plan={'version':'3.0','game_tag':'cdda-experimental-2026-09-23-0546','donors':[],'aliases':[]}
needed=set()
def trace(i,c,season,depth=10,variant=''):
 if not i or depth<=0:return
 candidates=[]
 if variant:
  if c=='vehicle':
   chunk=variant
   while chunk:
    candidates.append(i+'_'+chunk);chunk=chunk.rsplit('_',1)[0] if '_' in chunk else ''
  else:candidates.append(i+'_var_'+variant)
 candidates.append(i)
 for q in candidates:needed.update([q,q+'_season_'+season])
 if c=='trap':return
 o=real[c].get(i[3:] if c=='vehicle' else i)
 if not o:return
 ll=o['_ll']
 if c=='vehicle' and ll:
  for q,cat in [('vp_'+ll[0],c),(ll[0],c),(ll[0],'furniture')]:trace(q,cat,season,depth-1,variant)
 else:
  for n,q in enumerate(ll):trace(q,c,season,depth-1-n)
def get_needed(only=None):
 needed.clear()
 for st in states:
  if find(st):continue
  c,i,s,v=st
  if only and c!=only:continue
  q='vp_'+i if c=='vehicle' else i
  if c=='field':trace(q+'_int'+v,c,s);trace(q,c,s)
  else:trace(q,c,s,variant=v)
def visibility(root,dc):
 sheets=[];offset=0
 for b in dc['tiles-new']:
  im=Image.open(root/b['file']).convert('RGBA');w=b.get('sprite_width',dc['tile_info'][0]['width']);h=b.get('sprite_height',dc['tile_info'][0]['height']);n=im.width//w*(im.height//h)
  sheets.append((offset,offset+n,im,w,h,'ascii' in b));offset+=n
 def visible(r):
  if r<0:return False
  s=next((s for s in sheets if s[0]<=r<s[1]),None)
  if not s or s[-1]:return False
  start,end,im,w,h,_=s;n=r-start;x=n%(im.width//w)*w;y=n//(im.width//w)*h
  return im.getchannel('A').crop((x,y,x+w,y+h)).getbbox() is not None
 return visible
sources=[('legacy_magiclysm','v3_work/legacy/TILESETS/data/mods/Magiclysm'),('udp_shadow','v3_work/donors/shadow-759'),('udp_legacy','v3_work/donors/Xenikos'),('chibi','v3_work/donors/ChibiUltica'),('altica','v3_work/donors/Altica'),('larwick','v3_work/donors/Larwick_Overmap')]
for key,root in sources:
 root=Path(root);dc=json.load(open(root/'tile_config.json'));vis=visibility(root,dc);get_needed('overmap' if key=='larwick' else None);keep=[];blanks=[]
 # Equipment overlays for newly recovered objects, only when their exact base drawing was absent in v2.
 if key=='legacy_magiclysm':
  for i in list(needed):
   if i in real['item']:
    for prefix in ['overlay_wielded_','overlay_worn_','overlay_male_worn_','overlay_female_worn_']:needed.add(prefix+i)
 for b in dc['tiles-new']:
  if 'ascii' in b:continue
  for e in b.get('tiles',[]):
   for i in e['id'] if isinstance(e['id'],list) else [e['id']]:
    if i not in needed or i in tiles:continue
    if key=='udp_shadow' and (i.startswith('hair_dye_') or i=='glock_34'):continue
    newids=[i]+[i+'_'+s['id'] for s in e.get('additional_tiles',[])]
    if any(q in tiles for q in newids):continue
    if any(allrefs(en) and not any(vis(r) for r in allrefs(en)) for en in [e]+e.get('additional_tiles',[])):
     blanks.append(i);continue
    keep.append(i)
    for q in newids:tiles[q]=key+'_'+b['file'];origins[q]=key+':'+q;added[q]=(key,i)
    base_top[i]=(b,e)
 plan['donors'].append({'key':key,'root':str(root),'ids':keep,'blank_skipped':blanks})
 print(key,len(keep),'blank',len(blanks),flush=True)
# All substitutions below are explicitly reviewed; no nearest-name or broad monster matching.
def alias(target,source,reason):
 if target in tiles or source not in base_top:return False
 b,e=base_top[source];newids=[(target,source)]+[(target+'_'+s['id'],source+'_'+s['id']) for s in e.get('additional_tiles',[])]
 if any(t in tiles for t,s in newids):return False
 for t,s in newids:tiles[t]=tiles[s];origins[t]=origins[s];added[t]=('alias',target)
 base_top[target]=(b,e);plan['aliases'].append({'target':target,'source':source,'reason':reason});return True
if Path('v3_work/aliases.json').exists():
 for a in json.load(open('v3_work/aliases.json')):alias(**a)
rejected=[]
while True:
 bad=set()
 for st,old in baseline.items():
  f=find(st)
  if not f:raise AssertionError(st)
  if origins[f[-1]]!=old:bad.add(added[f[-1]])
 if not bad:break
 for key,owner in bad:
  rejected.append([key,owner])
  if key=='alias':plan['aliases']=[a for a in plan['aliases'] if a['target']!=owner]
  else:
   for d in plan['donors']:
    if d['key']==key:d['ids'].remove(owner)
  for q in [q for q,a in added.items() if a==(key,owner)]:tiles.pop(q);origins.pop(q);added.pop(q)
plan['visual_review_exclusions']={'udp_shadow':['hair_dye_brown','hair_dye_red','hair_dye_black','hair_dye_white','hair_dye_pink','hair_dye_gray','glock_34'],'reason':'Six hair dye IDs share a pink placeholder; Glock sprite contains stray text. Excluded after contact-sheet review.'}
plan['preserved_states']=len(baseline);plan['rejected']=rejected
Path('v3_work/plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2))
left=[];gains=collections.Counter();baseline_objects={s[:2] for s in baseline}
for c,objects in real.items():
 for i,o in objects.items():
  ss=[s for s in states if s[0]==c and s[1]==i] if False else None
  old=(c,i) in baseline_objects
  now=find((c,i,'summer',''))
  if now and not old:gains[c]+=1
  if not now:left.append({'category':c,'id':i,'name':env['name'](o),'copy-from':o.get('copy-from'),'looks_like':o['_ll'],'description':o.get('description'),'flags':o.get('flags',[])})
Path('v3_work/remaining.json').write_text(json.dumps(left,ensure_ascii=False,indent=2));print('rejected',rejected,'gains',gains,'aliases',len(plan['aliases']),flush=True)
