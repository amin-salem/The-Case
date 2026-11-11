"""Read-only diff guard: only existing avatar.portrait strings may change."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def verify(old, new, name):
    a, b = json.loads(old), json.loads(new)
    if [s['id'] for s in a['suspects']] != [s['id'] for s in b['suspects']]:
        raise ValueError(f'{name}: cast changed')
    changes=0
    for orig, current in zip(a['suspects'], b['suspects']):
        old_id = orig['avatar']['portrait']
        new_id = current['avatar']['portrait']
        if not isinstance(new_id, str) or not new_id:
            raise ValueError(f'{name}: portrait must be non-empty')
        changes += old_id != new_id
        current['avatar']['portrait'] = old_id
    if a != b:
        raise ValueError(f'{name}: protected case data changed')
    return changes

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    source=parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--base',help='base git ref; default target: HEAD')
    source.add_argument('--baseline-dir',type=Path,help='flat directory of verified original JSON files')
    parser.add_argument('--head', default='HEAD')
    args=parser.parse_args()
    count=slots=0
    dirs=['server/app/content/cases','server/app/content/weekly']
    if args.base:
        paths=git('diff','--name-only',args.base,args.head,'--',*dirs).decode().splitlines()
        pairs=((p,git('show',args.base+':'+p),git('show',args.head+':'+p)) for p in paths if p.endswith('.json'))
    else:
        paths=[p for d in dirs for p in (ROOT/d).glob('*.json')]
        if {p.name for p in paths}!={p.name for p in args.baseline_dir.glob('*.json')}:
            raise ValueError('case inventory changed')
        pairs=((p.name,(args.baseline_dir/p.name).read_bytes(),p.read_bytes()) for p in paths)
    for path,old,new in pairs:
        n=verify(old,new,path)
        count+=bool(n)
        slots+=n
    print(f'{count} cases, {slots} portrait values changed; no protected JSON fields changed.')
