"""Read-only matching diagnostic. Hypothetical capacity is not permission to publish."""
import csv,json
from pathlib import Path
from scipy.optimize import linear_sum_assignment
from art_rules import age_band, available as release_available, can_assign

ROOT=Path(__file__).resolve().parents[1]
O=ROOT/'docs/reviews/portrait-quality'
def read(path):return json.loads(path.read_text())
reg={p['id']:p for p in read(ROOT/'docs/art-registry.json')['portraits']}
rel=read(ROOT/'docs/portrait-release.json')
cases=[read(p) for mode in ('cases','weekly') for p in sorted((ROOT/'server/app/content'/mode).glob('*.json'))]
def in_scope(c):return c['id']<='c062' or 'w001'<=c['id']<='w006'
def culprit(c):return next(s for s in c['suspects'] if s['id']==c['solution']['culprit'])
def compatible(c,s,k):
    return can_assign(reg[k],s,s['avatar']['portrait'])
def available(c,s,k):
    return release_available(k,c,rel,s['avatar']['portrait'])
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
    for label,keys,predicate in [('release-compatible (68 cases, 9 other culprits reserved)',pool,available),('without four supplementary portraits, rollout ignored',[k for k in pool if k not in additional],lambda *_:True),('all staged portraits, rollout ignored',pool,lambda *_:True)]:
        m=solve(cases,keys,predicate);print(f'{label}: {sum(x is not None for x in m.values())}/{len(m)}')

    # Global bound, with no out-of-scope reservations. A Hall witness proves
    # that a complete compatible unique culprit album is impossible.
    keys=sorted(reg)
    choices=[]
    for c in cases:
        s=culprit(c)
        choices.append({k for k in keys if compatible(c,s,k) and available(c,s,k)})
    matrix=[[0 if k in choices[i] else 1000000 for k in keys]+[10000]*len(cases) for i in range(len(cases))]
    rows,cols=linear_sum_assignment(matrix)
    matched={i:keys[j] for i,j in zip(rows,cols) if j<len(keys) and matrix[i][j]<10000}
    reverse={p:i for i,p in matched.items()};u=set(range(len(cases)))-set(matched)
    while True:
        v=set().union(*(choices[i] for i in u)) if u else set()
        expanded=u|{reverse[k] for k in v if k in reverse}
        if expanded==u:break
        u=expanded
    proof={'total_cases':len(cases),'maximum_unique_compatible_culprits':len(matched),
           'hall_witness':{'cases':[cases[i]['id'] for i in sorted(u)],'portraits':sorted(v),
                           'case_count':len(u),'portrait_count':len(v),'deficit':len(u)-len(v)},
           'policy':'Gender, age gap <=7, roles_ok/roles_not_ok and current release ledger. Ignoring cast lookalikes makes this an upper bound.'}
    (ROOT/'docs/reviews/art-finish/capacity-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
    print('Global bound:',len(matched),'/',len(cases),'Hall deficit:',len(u)-len(v))

    from scipy.optimize import milp,Bounds,LinearConstraint
    import numpy as np
    from collections import Counter
    from finish_portrait_mapping import blocked_pairs
    pairs=blocked_pairs()
    new={p['id'] for p in read(ROOT/'docs/reviews/art-finish/generation-prompts.json')}
    demand=Counter()
    for row in csv.DictReader((O/'future-slots.csv').open()):
        if row['written']=='False' and row['gender'] in ('m','f'):
            demand[row['gender'],age_band(int(row['age']))]+=1
    def distinct(keys):
        keys=sorted(keys);edges=[tuple(p) for p in pairs if p<=set(keys)]
        a=np.zeros((len(edges),len(keys)))
        for i,(u,v) in enumerate(edges):a[i,keys.index(u)]=a[i,keys.index(v)]=1
        result=milp(-np.ones(len(keys)),integrality=np.ones(len(keys)),bounds=Bounds(0,1),constraints=LinearConstraint(a,-np.inf,1))
        if not result.success:raise RuntimeError(result.message)
        return round(-result.fun)
    groups=[]
    for gender in ('f','m'):
        for band in ('young','mid','old'):
            group={k for k,p in reg.items() if p['apparent_gender']==gender and p['age_band']==band}
            before=distinct(group-new);after=distinct(group)
            row=dict(gender=gender,age_band=band,before_files=len(group-new),before_distinct=before,
                     target=12,shortage=max(0,12-before),generated=len(group&new),after_distinct=after,
                     unwritten_slots=demand[gender,band])
            groups.append(row);print(row)
    result={'groups':groups,'unknown_gender_slots':2,
            'note':'Distinct count = maximum independent set under reviewed similarity pairs. Includes retained occupational images and staged assets. This is not current neutral release capacity.'}
    (ROOT/'docs/reviews/art-finish/group-capacity.json').write_text(json.dumps(result,indent=2)+'\n')
