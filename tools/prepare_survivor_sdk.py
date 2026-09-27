"""Prepare external API 1.7 compile declarations for both native modules. No runtime."""
import hashlib,json,sys
from pathlib import Path
recipe=json.loads(Path(__file__).with_name('native_sdk_recipe.json').read_text())
header=Path(sys.argv[1])/'ncmm_api.h'
raw=header.read_bytes().replace(b'\r\n',b'\n')
if hashlib.sha256(raw).hexdigest()!=recipe['seed_sha256']:
    raise SystemExit('External SDK differs from pinned seed; refusing patch')
lines=raw.decode('utf-8').splitlines(keepends=True)
for edit in reversed(recipe['edits']):
    lines[edit['start']:edit['end']]=edit['replacement']
result=''.join(lines).encode('utf-8')
assert hashlib.sha256(result).hexdigest()==recipe['result_sha256']
header.write_bytes(result)
print('Prepared external API 1.7 declarations; matching runtime still required')
