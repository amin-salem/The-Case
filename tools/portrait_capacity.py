"""Read-only matching diagnostic. Hypothetical capacity is not permission to publish."""
import csv,json
from pathlib import Path
from scipy.optimize import linear_sum_assignment

ROOT=Path(__file__).resolve().parents[1]
O=ROOT/'docs/reviews/portrait-quality'
def read(path):return json.loads(path.read_text())
reg={p['id']:p for p in read(ROOT/'docs/art-registry.json')['portraits']}
ap=read(ROOT/'docs/art-role-approvals.json')
rel=read(ROOT/'docs/portrait-release.json')
cases=[read(p) for mode in ('cases','weekly') for p in sorted((ROOT/'server/app/content'/mode).glob('*.json'))]
def in_scope(c):return c['id']<='c062' or 'w001'<=c['id']<='w006'
def culprit(c):return next(s for s in c['suspects'] if s['id']==c['solution']['culprit'])
def compatible(c,s,k):
    p=reg[k];a=ap.get(c['id']+'/'+s['id'],{})
    return (p['apparent_gender']==s['avatar']['gender'] and abs(p['apparent_age']-s['age'])<=7 and
        (not p['uniform'] or (a.get('role')==s['role'] and bool(set(a.get('role_tags',[])) & set(p['role_tags'])))))
def available(c,s,k):
    record=rel['portraits'].get(k)
    return (not record or c['publish']>=record['usable_from'] or (record['first_build'] is not None and
        s['avatar']['portrait']==k and c['publish']<rel['check_from']))
def solve(cases,keys,predicate):
    cs=[c for c in cases if in_scope(c)];reserved={culprit(c)['avatar']['portrait'] for c in cases if not in_scope(c)}
    def cost(c,k):
        s=culprit(c)
        if k in reserved or not compatible(c,s,k) or not predicate(c,s,k):return 1000000
        return abs(reg[k]['apparent_age']-s['age'])+4*(s['avatar']['portrait']!=k)
    matrix=[[cost(c,k) for k in keys]+[10000]*len(cs) for c in cs]
    row,col=linear_sum_assignment(matrix)
    return {cs[i]['id']:(keys[j] if j<len(keys) else None) for i,j in zip(row,col)}
if __name__=='__main__':
    pool=sorted(reg);additional={p['id'] for p in read(O/'additional-briefs.json')['portraits']}
    for label,keys,predicate in [('release-compatible',pool,available),('six new faces, rollout ignored',[k for k in pool if k not in additional],lambda *_:True),('ten new faces, rollout ignored',pool,lambda *_:True)]:
        m=solve(cases,keys,predicate);print(f'{label}: {sum(x is not None for x in m.values())}/{len(m)}')
