"""Optimise valid portrait changes. Invalid ORIGINALS are explicit unresolved fallbacks.

Unknown rollout dates, duplicate culprits and lookalikes are never allowed for
new assignments. Only portrait strings are edited; story data is compared.
"""
import argparse,csv,json,re
from collections import defaultdict
from pathlib import Path
import numpy as np
from scipy.optimize import Bounds,LinearConstraint,milp
from scipy.sparse import coo_matrix
from art_rules import available,can_assign,incompatibilities

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text())
def blocked_pairs():
    review=ROOT/'docs/reviews/portrait-quality'
    pairs={frozenset(p) for p in read(review/'editorial-neighbours.json')}
    pairs.update(frozenset((p['a'],p['b'])) for p in read(review/'machine-candidates.json')['candidates'] if p['decision']=='avoid_same_cast')
    return pairs

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-dir',type=Path,required=True)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    reg={p['id']:p for p in read(ROOT/'docs/art-registry.json')['portraits']}
    releases=read(ROOT/'docs/portrait-release.json');pairs=blocked_pairs()
    paths=sorted(p for d in ['cases','weekly'] for p in (ROOT/'server/app/content'/d).glob('*.json'))
    slots=[];options=[];cost=[];by_slot=defaultdict(list);by_case_key=defaultdict(list);by_culprit_key=defaultdict(list)
    for path in paths:
        c=read(path);candidate=read(args.candidate_dir/path.relative_to(ROOT))
        desired={s['id']:s['avatar']['portrait'] for s in candidate['suspects']}
        for s in c['suspects']:
            slot=len(slots);slots.append((path,c,s,desired[s['id']]))
            original=s['avatar']['portrait']
            for k,p in sorted(reg.items()):
                valid=can_assign(p,s,original) and available(k,c,releases,original)
                if not valid and k!=original:continue
                j=len(options);options.append((slot,k,valid));by_slot[slot].append(j);by_case_key[c['id'],k].append(j)
                if s['id']==c['solution']['culprit']:by_culprit_key[k].append(j)
                cost.append((0 if valid else 100000)+(0 if k==original else 10)+(0 if k==desired[s['id']] else 1)+abs(p['apparent_age']-s['age'])/100)
    indices=[];columns=[];values=[];lo=[];hi=[]
    def constraint(js,lower,upper):
        row=len(lo);indices.extend([row]*len(js));columns.extend(js);values.extend([1]*len(js));lo.append(lower);hi.append(upper)
    for js in by_slot.values():constraint(js,1,1)
    for js in by_case_key.values():constraint(js,0,1)
    for js in by_culprit_key.values():constraint(js,0,1)
    # Preserve the existing test_content legacy fallback-category budget.
    # This does not waive the new numeric-age or role checks above.
    bounds={'young':(0,35),'mid':(32,54),'old':(50,99)}
    legacy_misses=[]
    for j,(slot,k,_) in enumerate(options):
        suspect=slots[slot][2];lower,upper=bounds[suspect['avatar']['age']]
        if not lower<=reg[k]['apparent_age']<=upper:legacy_misses.append(j)
    constraint(legacy_misses,0,8)
    for cid in {c['id'] for _,c,_,_ in slots}:
        for pair in pairs:
            a,b=tuple(pair);js=by_case_key.get((cid,a),[])+by_case_key.get((cid,b),[])
            if js:constraint(js,0,1)
    matrix=coo_matrix((values,(indices,columns)),shape=(len(lo),len(options))).tocsc()
    result=milp(np.array(cost),integrality=np.ones(len(options)),bounds=Bounds(0,1),constraints=LinearConstraint(matrix,lo,hi),options={'time_limit':60,'mip_rel_gap':0})
    if not result.success:raise RuntimeError(result.message)
    selected={options[j][0]:options[j][1:] for j,x in enumerate(result.x) if x>.5}
    report=[];by_path=defaultdict(dict)
    for slot,(path,c,s,desired) in enumerate(slots):
        k,valid=selected[slot];original=s['avatar']['portrait'];assert valid or k==original
        by_path[path][s['id']]=k
        before=incompatibilities(reg[original],s);after=incompatibilities(reg[k],s)
        report.append(dict(case=c['id'],slot=s['id'],name=s['name'],age=s['age'],role=s['role'],before=original,candidate=desired,after=k,before_issues='; '.join(before),after_issues='; '.join(after),status='unresolved: original retained; hard constraints prevent a complete solution' if not valid else 'corrected' if k!=original else 'valid retained'))
    out=ROOT/'docs/reviews/art-finish'
    with (out/'case-mapping.csv').open('w') as f:
        w=csv.DictWriter(f,list(report[0]));w.writeheader();w.writerows(report)
    (out/'mapping-solver.json').write_text(json.dumps({
        'status':int(result.status),'message':result.message,'optimal':bool(result.success),
        'mip_gap':float(result.mip_gap),'unresolved_original_slots':sum(bool(r['after_issues']) for r in report),
        'constraints':'Only a valid new assignment or retention of the original; global unique culprit, no repeated/lookalike cast, release ledger, gender, <=7-year age gap, role permissions, existing legacy fallback-category budget <=8.',
        'note':'Run against an unchanged main input to reproduce the before/after report; keep the candidate copy separate.'},indent=2)+'\n')
    if args.apply:
        for path,choices in by_path.items():
            original=path.read_text();c=json.loads(original);it=iter(c['suspects'])
            def replace(m):
                s=next(it);assert m[2]==s['avatar']['portrait'];return m[1]+choices[s['id']]+m[3]
            new=re.sub(r'("portrait"\s*:\s*")([^"]+)(")',replace,original)
            old_data=json.loads(original);new_data=json.loads(new)
            for a,b in zip(old_data['suspects'],new_data['suspects']):b['avatar']['portrait']=a['avatar']['portrait']
            assert old_data==new_data,path
            if original!=new:path.write_text(new)
    print('Optimal assignment. Slots',len(slots),'changed',sum(r['before']!=r['after'] for r in report),'unresolved',sum(bool(r['after_issues']) for r in report))
    for r in report:
        if r['after_issues']:print(r['case'],r['slot'],r['age'],r['after'],r['after_issues'])
