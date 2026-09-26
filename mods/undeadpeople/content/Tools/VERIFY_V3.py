#!/usr/bin/env python3
"""Verify the final hybrid's source mappings, pixels, and effective fallback behavior.
Usage: python VERIFY_V3.py GAME_SOURCE V2_ROOT V3_ROOT REPORT_DIRECTORY
Requires audit_coverage.py and BUILD_V3.py beside this file, and Pillow.
"""
import contextlib,io,json,runpy,sys,collections
from pathlib import Path
from PIL import Image
from BUILD_V3 import index,allrefs,capacity
src,base,new,out=map(Path,sys.argv[1:]);out.mkdir(exist_ok=True,parents=True)
audit=Path(__file__).with_name('audit_coverage.py')
def load(root,subdir):
 sys.argv=[str(audit),str(src),str(root),str(out/subdir)]
 with contextlib.redirect_stdout(io.StringIO()):return runpy.run_path(str(audit))
a=load(base,'baseline');b=load(new,'final');ai=index(a['cfg']);bi=index(b['cfg'])
def visual_sig(state,env,idx):
 c,i,s,v=state;f=env['lookup'];q='vp_'+i if c=='vehicle' else i
 r=(f(q+'_int'+v,c,s) or f(q,c,s)) if c=='field' else f(q,c,s,variant=v)
 if not r:return None
 block,e=idx[r[-1]]
 geom={k:v for k,v in block.items() if k not in ('tiles','//','ascii')}
 tile={k:v for k,v in e.items() if k not in ('id','//')}
 return json.dumps([geom,tile],sort_keys=True)
protected=0;regressions=[];gained=0
for c,objects in a['real'].items():
 for i,o in objects.items():
  vv=['']
  if c in ('vehicle','item') and o.get('variants'):vv=[v.get('id','') for v in o['variants'] if isinstance(v,dict)] or ['']
  if c=='field':vv=[str(v) for v in range(1,len(o.get('intensity_levels',[]))+1)] or ['1']
  for season in ['spring','summer','autumn','winter']:
   for v in vv:
    state=(c,i,season,v);old=visual_sig(state,a,ai);now=visual_sig(state,b,bi)
    if old:
     protected+=1
     if old!=now:regressions.append(state)
    elif now:gained+=1
assert not regressions,regressions[:10]
# Every original mapping and image remains byte-identical.
for i,(block,e) in ai.items():
 nb,ne=bi[i];assert e==ne,i
for block in a['cfg']['tiles-new']:
 assert (base/block['file']).read_bytes()==(new/block['file']).read_bytes(),block['file']
assert (base/'layering.json').read_bytes()==(new/'layering.json').read_bytes()
# PNG cells used by added entries must actually contain visible pixels.
info=b['cfg']['tile_info'][0];sheets=[];offset=0
for block in b['cfg']['tiles-new']:
 if 'ascii' in block:continue
 im=Image.open(new/block['file']).convert('RGBA');w=block.get('sprite_width',info['width']);h=block.get('sprite_height',info['height']);cap=(im.width//w)*(im.height//h)
 sheets.append((offset,offset+cap,im,w,h));offset+=cap
visibility={}
def visible(ref):
 if ref not in visibility:
  start,end,im,w,h=next(s for s in sheets if s[0]<=ref<s[1]);n=ref-start;x=n%(im.width//w)*w;y=n//(im.width//w)*h
  visibility[ref]=im.getchannel('A').crop((x,y,x+w,y+h)).getbbox() is not None
 return visibility[ref]
blank=[]
for i,(block,e) in bi.items():
 if i in ai:continue
 rr=allrefs(e)
 if rr and not any(visible(r) for r in rr):blank.append(i)
assert not blank,('new blank graphics',blank)
result={'protected_states_checked':protected,'protected_states_changed':len(regressions),'newly_drawable_states':gained,'v2_runtime_ids_preserved':len(ai),'new_runtime_ids':len(bi)-len(ai),'new_blank_tiles':blank,'original_atlases_byte_identical':True,'layering_byte_identical':True,'runtime_game_launched':False}
(out/'FINAL_VALIDATION.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
