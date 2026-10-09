#!/usr/bin/env python3
"""Stage and run Iznanka's exact-source lifecycle probe. Never patches engine code."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHA = '074aa98bd5be3de4c35f154082db32a0e63bb0f1'
SOURCES = 'test_main.cpp fake_messages.cpp force_load_game_test.cpp map_helpers_tests.cpp player_helpers.cpp options_helpers.cpp mapgen_helpers.cpp iznanka_lifecycle_test.cpp'

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--cdda-root', required=True, type=Path)
    p.add_argument('--out', type=Path)
    p.add_argument('--prepare', action='store_true')
    p.add_argument('--combined', action='store_true')
    p.add_argument('--already-staged', action='store_true')
    a = p.parse_args()
    game = a.cdda_root.resolve()
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=game, text=True).strip()
    if actual != SHA:
        raise SystemExit(f'Expected CDDA {SHA}; got {actual}')
    if not a.already_staged:
        shutil.copytree(ROOT / 'mods/iznanka/content', game / 'data/mods/Iznanka', dirs_exist_ok=True)
        shutil.rmtree(game / 'data/cache/mods/Iznanka', ignore_errors=True)
    if a.prepare:
        shutil.copy2(ROOT / 'tools/runtime_probes/iznanka_lifecycle_test.cpp', game / 'tests/iznanka_lifecycle_test.cpp')
        makefile = game / 'tests/Makefile'
        text = makefile.read_text()
        old = 'SOURCES = $(wildcard *.cpp)'
        replacement = 'SOURCES = ' + SOURCES
        if old not in text and replacement not in text:
            raise SystemExit('Unexpected tests/Makefile; refusing to change it')
        makefile.write_text(text.replace(old, replacement))
        print('Prepared the test collection; engine source is unchanged.')
        return
    if a.out is None:
        p.error('--out is required when running')
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    mods = 'dda,iznanka'
    if a.combined:
        import deep_cdda_runtime as runtime
        if not a.already_staged:
            runtime.stage_source(game, 'experimental-2026-10-06-1807')
        _, rows = runtime.build_suites('experimental-2026-10-06-1807')
        mods = ','.join(next(r['game_mod_ids'] for r in rows if r['name'] == 'combined-all-json'))
    files = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest()
             for f in sorted((ROOT / 'mods/iznanka/content').rglob('*')) if f.is_file()}
    cmd = [str(game / 'tests/cata_test'), '[iznanka_lifecycle]', '--mods=' + mods,
           '--rng-seed', '4242', '--user-dir=' + tempfile.mkdtemp(prefix='user-', dir=out) + '/']
    with (out / 'runtime.log').open('w') as log:
        result = subprocess.run(cmd, cwd=game, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    (out / 'evidence.json').write_text(json.dumps({'target': SHA, 'exit_code': result.returncode,
        'mods': mods, 'payload_sha256': files, 'probe_sha256': hashlib.sha256((ROOT / 'tools/runtime_probes/iznanka_lifecycle_test.cpp').read_bytes()).hexdigest()}, indent=2) + '\n')
    print((out / 'runtime.log').read_text())
    raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()
