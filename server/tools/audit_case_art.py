"""Read-only asset coverage/reuse report; does not expose case solutions."""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def audit():
    portraits = {p.stem: p for p in (ROOT / 'app/assets/portraits').glob('*.webp')}
    scenes = {p.stem: p for p in (ROOT / 'app/assets/scenes').glob('*.webp')}
    uses, scene_uses, missing, within_case = defaultdict(list), defaultdict(list), [], []
    counts = {}
    for mode in ('cases', 'weekly', 'story'):
        files = sorted((ROOT / 'server/app/content' / mode).rglob('*.json'))
        counts[mode] = 0
        for path in files:
            d = json.loads(path.read_text())
            if 'suspects' not in d:
                continue
            counts[mode] += 1
            scene = d.get('scene')
            scene_uses[scene].append(d['id'])
            if scene not in scenes:
                missing.append({'case': d['id'], 'scene': scene})
            local = set()
            for s in d['suspects']:
                p = s.get('avatar', {}).get('portrait')
                ref = {'case': d['id'], 'suspect': s['id'], 'name': s['name']}
                uses[p].append(ref)
                if p not in portraits:
                    missing.append({**ref, 'portrait': p})
                if p in local:
                    within_case.append({**ref, 'portrait': p})
                local.add(p)
    hashes = defaultdict(list)
    for p in [*portraits.values(), *scenes.values()]:
        hashes[hashlib.sha256(p.read_bytes()).hexdigest()].append(str(p.relative_to(ROOT)))
    return {
        'case_counts': counts,
        'portrait_assets': len(portraits), 'scene_assets': len(scenes),
        'suspect_appearances': sum(map(len, uses.values())),
        'referenced_portraits': len(uses),
        'missing': missing, 'same_cast_reuse': within_case,
        'byte_identical_assets': [v for v in hashes.values() if len(v) > 1],
        'unused_portraits': sorted(set(portraits) - set(uses)),
        'portrait_usage': dict(sorted(uses.items(), key=lambda kv: (-len(kv[1]), str(kv[0])))),
        'scene_usage': dict(sorted(scene_uses.items(), key=lambda kv: str(kv[0]))),
    }


if __name__ == '__main__':
    print(json.dumps(audit(), ensure_ascii=False, indent=2))
