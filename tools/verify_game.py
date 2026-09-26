#!/usr/bin/env python3
"""Validate exact selected source variants with a real game, without installing them."""
import argparse, json, re, shutil, subprocess, tempfile
from pathlib import Path
import modsuite as s

def run(exe,game,data,user,ids,timeout):
    user.mkdir(parents=True,exist_ok=True)
    args=[str(exe),'--basepath',str(game)+'/', '--datadir',str(data)+'/', '--userdir',str(user)+'/', '--check-mods',*ids]
    try:
        p=subprocess.run(args,cwd=game,capture_output=True,text=True,errors='replace',timeout=timeout)
        code=p.returncode;out=p.stdout;err=p.stderr
    except subprocess.TimeoutExpired as e:
        code=124;out=(e.stdout or b'').decode(errors='replace') if isinstance(e.stdout,bytes) else (e.stdout or '');err='Validator timed out'
    (user/'stdout.log').write_text(out,encoding='utf-8');(user/'stderr.log').write_text(err,encoding='utf-8')
    logs=out+'\n'+err+'\n'+'\n'.join(p.read_text(errors='replace') for p in user.rglob('debug.log'))
    errors=[l for l in logs.splitlines() if re.search(r'\(json-error\)|ERROR\s*:|Error loading|Unknown mod:|Missing dependencies:|Fatal:|timed out',l)]
    return dict(exit_code=code,errors=errors)

def main():
    p=argparse.ArgumentParser();p.add_argument('--game-root',required=True);p.add_argument('--target',required=True);p.add_argument('--mods',required=True);p.add_argument('--out',required=True);p.add_argument('--timeout',type=int,default=240);a=p.parse_args()
    mods,targets=s.validate();target=targets[a.target];game=Path(a.game_root).resolve();out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
    version=(game/'VERSION.txt').read_text();match=re.search(r'commit sha:\s*([0-9a-f]{40})',version,re.I)
    if not match or match[1].lower()!=target['commit']:raise ValueError('VERSION.txt does not identify the exact target commit')
    exe=next((game/n for n in ('cataclysm-tiles.vanilla.exe','cataclysm-tiles.exe','cataclysm.exe','cataclysm') if (game/n).is_file()),None)
    if not exe:raise ValueError('Game executable missing')
    chosen=[]
    def visit(id):
        if id in chosen:return
        for d in mods[id]['dependencies']:visit(d)
        chosen.append(id)
    for id in a.mods.split(','):visit(id.strip())
    variants={id:next(v for v in mods[id]['variants'] if a.target in v['targets']) for id in chosen}
    if any(mods[id]['kind']!='json' for id in chosen):raise ValueError('This verifier accepts JSON mods only; native and tileset checks are separate')
    with tempfile.TemporaryDirectory(prefix='CDDA-Mods-verify-') as tmp:
        data=Path(tmp)/'data';shutil.copytree(game/'data',data,ignore=shutil.ignore_patterns('cache','gfx'))
        if (game/'gfx').is_dir():shutil.copytree(game/'gfx',data/'gfx')
        baseline=run(exe,game,data,out/'baseline',['dda'],a.timeout)
        results=[];report=dict(schema=1,target=a.target,commit=target['commit'],baseline=baseline,components=results)
        if baseline['exit_code'] or baseline['errors']:
            s.write(out/'report.json',report);raise RuntimeError('Vanilla baseline failed. No compatibility status changed.')
        for id in chosen:
            m=mods[id];v=variants[id]
            for f in list((data/'mods').rglob('modinfo.json')):
                records=s.read(f);records=records if isinstance(records,list) else [records]
                if any(o.get('id') in m['game_mod_ids'] for o in records if o.get('type')=='MOD_INFO'):shutil.rmtree(f.parent)
            shutil.copytree(s.ROOT/'mods'/id/v['path'],data/'mods'/m['folder'])
        for id in chosen:
            v=variants[id];result=run(exe,game,data,out/id,mods[id]['game_mod_ids'],a.timeout)
            results.append(dict(result,id=id,kind='json',content_sha256=s.tree_hash(s.ROOT/'mods'/id/v['path'])))
        stack=data/'mods/suite_validation_stack';stack.mkdir()
        s.write(stack/'modinfo.json',[dict(type='MOD_INFO',id='suite_validation_stack',name='Suite validation',authors=['Neversalimus'],description='Temporary combined validation.',dependencies=['dda']+[i for id in chosen for i in mods[id]['game_mod_ids']])])
        report['combined']=run(exe,game,data,out/'combined',['suite_validation_stack'],a.timeout)
        s.write(out/'report.json',report)
        if any(x['exit_code'] or x['errors'] for x in results+[report['combined']]):raise RuntimeError('Some checks failed. See report.json; no status changed.')
        print('Checks passed. Review logs, then record-validation to publish load-tested status.')
if __name__=='__main__':main()
