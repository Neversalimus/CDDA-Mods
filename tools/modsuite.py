#!/usr/bin/env python3
"""Standard-library maintenance CLI. No player-side Python dependency."""
from __future__ import annotations
import argparse, hashlib, json, re, shutil, subprocess, sys, urllib.request, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SAFE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$')
def read(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p, v):
    p=Path(p); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def files(p): return sorted(x for x in Path(p).rglob('*') if x.is_file())
def tree_hash(p):
    return hashlib.sha256(''.join(x.relative_to(p).as_posix()+'\0'+digest(x)+'\n' for x in files(p)).encode()).hexdigest()
def payload_tree_hash(payload):
    inventory={name[8:]:hashlib.sha256(data).hexdigest() for name,data in payload}
    return hashlib.sha256(''.join(name+'\0'+inventory[name]+'\n' for name in sorted(inventory)).encode()).hexdigest()
def _png_dimensions(data):
    assert data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR'
    return int.from_bytes(data[16:20],'big'),int.from_bytes(data[20:24],'big')
def _shift_sprite_value(value,delta):
    if isinstance(value,int): return value+delta
    if isinstance(value,list):
        shifted=[]
        for item in value:
            if isinstance(item,int): shifted.append(item+delta)
            elif isinstance(item,dict):
                item=dict(item)
                if 'sprite' in item:item['sprite']=_shift_sprite_value(item['sprite'],delta)
                shifted.append(item)
            else:shifted.append(item)
        return shifted
    return value
def bake_undeadpeople_secronom(payload):
    entries=dict(payload)
    cfg=json.loads(entries['payload/tile_config.json'].decode('utf-8-sig'))
    tile_info=cfg['tile_info'][0]
    base_total=0
    for part in cfg['tiles-new']:
        data=entries['payload/'+part['file']]
        width,height=_png_dimensions(data)
        sw=part.get('sprite_width',tile_info['width']);sh=part.get('sprite_height',tile_info['height'])
        assert width%sw==0 and height%sh==0,(part['file'],width,height,sw,sh)
        base_total+=(width//sw)*(height//sh)
    sec=read(ROOT/'mods/secronom/content/mod_tileset.json')[0]
    assert not any(str(part.get('file','')).startswith('compat_secronom_') for part in cfg['tiles-new'])
    for source in sec['tiles-new']:
        part=json.loads(json.dumps(source))
        old_name=part['file'];part['file']='compat_'+old_name
        part['//']=f'Hybrid v3 baked Secronom compatibility; source {old_name}; sprite refs +{base_total}'
        for tile in part.get('tiles',[]):
            if 'fg' in tile:tile['fg']=_shift_sprite_value(tile['fg'],base_total)
            if 'bg' in tile:tile['bg']=_shift_sprite_value(tile['bg'],base_total)
            for sub in tile.get('additional_tiles',[]):
                if 'fg' in sub:sub['fg']=_shift_sprite_value(sub['fg'],base_total)
                if 'bg' in sub:sub['bg']=_shift_sprite_value(sub['bg'],base_total)
        cfg['tiles-new'].append(part)
        entries['payload/'+part['file']]=(ROOT/'mods/secronom/content'/old_name).read_bytes()
    entries['payload/tile_config.json']=(json.dumps(cfg,ensure_ascii=False,indent=2)+'\n').encode()
    tileset=entries['payload/tileset.txt'].decode('utf-8-sig')
    old_view='VIEW: UndeadPeople Hybrid v3 (2026-09-23)'
    assert old_view in tileset
    entries['payload/tileset.txt']=tileset.replace(old_view,'VIEW: UndeadPeople Hybrid v3 (2026-10-01, Secronom baked)').encode()
    return sorted(entries.items())
def manifests(): return {read(p)['id']:read(p) for p in sorted((ROOT/'mods').glob('*/manifest.json'))}
def safe_path(root, rel):
    if not isinstance(rel,str) or '\\' in rel or ':' in rel or not rel or any(x in ('','.','..') for x in rel.split('/')): raise ValueError(f'Unsafe path: {rel!r}')
    p=(root/rel).resolve()
    if not p.is_relative_to(root.resolve()): raise ValueError(f'Path escapes root: {rel}')
    return p

def validate():
    mods=manifests(); targets={read(p)['id']:read(p) for p in (ROOT/'catalog/targets').glob('*.json')}
    assert mods and targets
    for t in targets.values():
        assert re.fullmatch('[0-9a-f]{40}',t['commit']), t
        assert t['channel'] in ('stable','experimental')
    count=0
    for id,m in mods.items():
        assert SAFE.fullmatch(id) and SAFE.fullmatch(m['folder'])
        assert m['kind'] in ('json','tileset','native')
        assert all(d in mods for d in m['dependencies']),id
        seen=set()
        for v in m['variants']:
            assert SAFE.fullmatch(v['id']) and SAFE.fullmatch(v['version']) and v['revision']>=1
            assert v['validation'] in ('pending','static','load-tested','runtime-tested','blocked')
            assert not seen.intersection(v['targets']), f'Ambiguous target mapping: {id}'
            seen.update(v['targets']); assert set(v['targets'])<=targets.keys()
            path=safe_path(ROOT/'mods'/id,v['path']); assert path.is_dir(),path
            assert files(path),f'Empty payload: {id}'
            for f in files(path):
                assert not f.is_symlink(),f
                safe_path(path,f.relative_to(path).as_posix())
                if f.suffix.lower()=='.json':
                    data=read(f); count+=1
                    if m['kind']=='json': assert isinstance(data,(list,dict)),f
            if m['kind']=='json':
                mi=read(path/'modinfo.json'); mi=mi if isinstance(mi,list) else [mi]
                actual={o['id'] for o in mi if o.get('type')=='MOD_INFO'}
                assert actual==set(m['game_mod_ids']),(id,actual)
            if m['kind']=='native':
                if v.get('available',True): assert (path/'ncmm_mod.dll').read_bytes()[:2]==b'MZ'
                assert read(path/'mod.json')['id']==id
            if m['kind']=='tileset':
                assert (path/'tileset.txt').exists()
                cfg=read(path/'tile_config.json')
                for entry in cfg['tiles-new']: assert safe_path(path,entry['file']).is_file(),entry['file']
    # DFS catches dependency cycles before player-side planning.
    def visit(id,stack):
        assert id not in stack,f'Cycle: {stack+[id]}'
        for d in mods[id]['dependencies']:visit(d,stack+[id])
    for id in mods:visit(id,[])
    print(f'Validated {len(mods)} components, {count} JSON files, {len(targets)} target(s).')
    return mods,targets

def make_zip(path, entries):
    path.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,data in sorted(entries):
            info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,data)

def build(out):
    mods,targets=validate(); out=Path(out).resolve();out.mkdir(parents=True,exist_ok=True)
    config=read(ROOT/'catalog/repository.json'); entries=[]; output_names={'catalog.json'}
    for id,m in mods.items():
        for v in m['variants']:
            p=ROOT/'mods'/id/v['path'];name=f"{id}-{v['version']}-r{v['revision']}-{v['id']}.zip"
            payload=[('payload/'+f.relative_to(p).as_posix(),f.read_bytes()) for f in files(p)]
            content_sha256=tree_hash(p)
            if id=='undeadpeople':
                payload=bake_undeadpeople_secronom(payload)
                content_sha256=payload_tree_hash(payload)
            inventory={n[8:]:hashlib.sha256(b).hexdigest() for n,b in payload}
            descriptor={k:m[k] for k in ('id','name','kind','folder','dependencies','game_mod_ids')}
            descriptor.update({k:v[k] for k in ('version','revision','targets','validation')})
            descriptor.update(variant=v['id'],content_sha256=content_sha256,files=inventory)
            if v.get('available',True):
                make_zip(out/name,payload+[('package.json',json.dumps(descriptor,sort_keys=True).encode())])
                output_names.add(name)
                entries.append(dict(descriptor,archive=name,sha256=digest(out/name)))
            else:
                entries.append(dict(descriptor,archive=None,sha256=None))
    catalog=dict(schema=1,release_tag='v'+config['suite_version'],suite_version=config['suite_version'],repository=config['repository'],targets=list(targets.values()),profiles=config['profiles'],packages=entries)
    write(out/'catalog.json',catalog)
    for f in (ROOT/'installer').glob('*'):
        if f.is_file(): shutil.copy2(f,out/f.name); output_names.add(f.name)
    write(out/'checksums.json',{name:digest(out/name) for name in sorted(output_names)})
    make_zip(out/'CDDA-Mods-Installer.zip',[(name,(out/name).read_bytes()) for name in sorted(output_names|{'checksums.json'})])
    print(f'Built {sum(bool(e["archive"]) for e in entries)} installable packages, {len(entries)} catalog entries: {out}')

def context(ids):
    mods=manifests(); chosen=list(mods) if ids=='all' else ids.split(',')
    print('# CDDA Mods — chat context\n\nRead AGENTS.md, docs/CHAT_WORKFLOW_RU.md and docs/STATUS.md first.\n')
    print('## Repository\n'+json.dumps(read(ROOT/'catalog/repository.json'),indent=2))
    for id in chosen:
        print('\n## '+id+'\n'+json.dumps(mods[id],ensure_ascii=False,indent=2))
    print('\nDo not infer compatibility from version ordering. NCMM host/runtime belongs to its separate repository.')

def prepare(tag,ids):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+',tag):raise ValueError('Invalid release tag')
    api='https://api.github.com/repos/CleverRaven/Cataclysm-DDA/'
    # Resolve the real tag commit, not target_commitish (which can be a moving branch).
    request=lambda url: json.load(urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'CDDA-Mods-maintenance'})))
    release=request(api+'releases/tags/'+tag); obj=request(api+'git/ref/tags/'+tag)['object']
    while obj['type']=='tag':obj=request(obj['url'])['object']
    assert obj['type']=='commit'
    target=tag.removeprefix('cdda-'); target_path=ROOT/'catalog/targets'/f'{target}.json'
    if target_path.exists(): raise ValueError('Target already exists; edit its selected mods without overwriting historical mappings')
    mods=manifests();chosen=list(mods) if ids=='all' else ids.split(',')
    for id in chosen:
        if id not in mods:raise ValueError('Unknown component: '+id)
    write(target_path,dict(schema=1,id=target,channel='experimental' if 'experimental' in tag else 'stable',tag=tag,commit=obj['sha'],label=release['name']))
    for id in chosen:
        m=mods[id]; previous=m['variants'][-1]; path='variants/'+target
        shutil.copytree(ROOT/'mods'/id/previous['path'],ROOT/'mods'/id/path)
        v=dict(previous,id=target,path=path,targets=[target],validation='pending',revision=previous['revision']+1)
        m['variants'].append(v); write(ROOT/'mods'/id/'manifest.json',m)
    print(f'Prepared {target}: {", ".join(chosen)}. Compatibility is PENDING. Old variants are preserved.')

def record(report):
    data=read(report);mods,targets=validate(); target=data['target']; assert target in targets
    assert data['commit']==targets[target]['commit']
    assert data['baseline']['exit_code']==0 and not data['baseline']['errors']
    assert data['combined']['exit_code']==0 and not data['combined']['errors']
    assert data['components'], 'Empty report'
    for result in data['components']:
        id=result['id'];v=next(v for v in mods[id]['variants'] if target in v['targets'])
        assert result['content_sha256']==tree_hash(ROOT/'mods'/id/v['path']), 'Stale report: '+id
        assert result['exit_code']==0 and not result['errors'],'Failed check: '+id
        assert result['kind']=='json', 'Native/tileset needs its own runtime evidence'
    # No edits before every result has been checked.
    for result in data['components']:
        id=result['id'];m=mods[id];v=next(v for v in m['variants'] if target in v['targets']);v['validation']='load-tested';write(ROOT/'mods'/id/'manifest.json',m)
    write(ROOT/'compat/reports'/Path(report).name,data)
    print('Recorded load-test evidence. This does not claim save or gameplay compatibility.')

if __name__=='__main__':
    p=argparse.ArgumentParser();sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('validate')
    b=sub.add_parser('build');b.add_argument('--out',default=str(ROOT/'dist'))
    c=sub.add_parser('context');c.add_argument('--mods',default='all')
    t=sub.add_parser('prepare-target');t.add_argument('--tag',required=True);t.add_argument('--mods',required=True)
    c=sub.add_parser('record-validation');c.add_argument('--report',required=True)
    a=p.parse_args()
    try:
        if a.command=='validate':validate()
        elif a.command=='build':build(a.out)
        elif a.command=='context':context(a.mods)
        elif a.command=='prepare-target':prepare(a.tag,a.mods)
        elif a.command=='record-validation':record(a.report)
    except (AssertionError,ValueError,KeyError,OSError,StopIteration) as e:
        print('ERROR:',e,file=sys.stderr);sys.exit(1)
