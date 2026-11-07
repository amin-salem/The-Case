"""Generate a REVIEW DRAFT only; never edits a case or invents a missing portrait."""
import json,csv
from pathlib import Path
import numpy as np
from scipy.optimize import linear_sum_assignment
R=Path(__file__).resolve().parents[1]; O=R/'docs/reviews/portrait-quality'
reg=json.load(open(R/'docs/art-registry.json'))['portraits']; by={x['id']:x for x in reg}
slots=json.load(open(O/'all-slots.json'))
# Explicit editorial allowances. Neutral wardrobe is valid for every occupation;
# an occupational suffix never grants permission for a visible uniform.
allowed={
'security':'c001/s4 c002/s2 c004/s4 c006/s1 c007/s3 c009/s4 c016/s5 c019/s2 c021/s5 c024/s2 c026/s3 c029/s2 c031/s2 c035/s5 c040/s5 c044/s2 c047/s5 w003/s6 w005/s6',
'medical':'c008/s2 c008/s4 c008/s5 c025/s4 c028/s1 c028/s2 c028/s3 c028/s4 c028/s5 c033/s4 c040/s3 c050/s1 c051/s1 c051/s2 c051/s3 c051/s4 c051/s5 w001/s2 w001/s7 w004/s3 w006/s6',
'catering':'c012/s1 c012/s2 c012/s4 c013/s4 c031/s5 c032/s1 c032/s2 c032/s4 c032/s5 c033/s2 c045/s3 c060/s4 w002/s3 w003/s7 w004/s6 w006/s4',
'hospitality':'c003/s1 c011/s3 c023/s2 c032/s1 c039/s3 c043/s4 w002/s3 w006/s4',
'railway':'c003/s1 c015/s1 c023/s2 c043/s2 c043/s4',
'nautical':'c007/s5 c027/s1 c027/s2 c027/s3 c027/s4 c027/s5 c049/s1 c049/s2 c049/s3 c049/s4 c049/s5',
'construction':'c007/s2 c015/s5 c026/s2 c034/s4 c046/s4',
'restoration':'c004/s5 c020/s1 c020/s2 c024/s5 c040/s4 c044/s5 c061/s2 w005/s2',
'laboratory':'c003/s3 c016/s1 c016/s2 c016/s3 c016/s4 c018/s5 c036/s1 c036/s2 c036/s3 c036/s4 c036/s5 c052/s1 c052/s3 c052/s4 c052/s5 c052/s6',
'music':'c017/s3 c037/s5'}
for s in slots:s['role_tags']=[k for k,v in allowed.items() if s['case']+'/'+s['suspect'] in v.split()]
# Preserve w007, outside requested remap scope, reserve its culprit.
reserved={s['portrait'] for s in slots if s['case']=='w007' and s['culprit']}
close={frozenset((x['a'],x['b'])) for x in json.load(open(O/'machine-candidates.json'))['candidates'] if x['decision']=='avoid_same_cast'}
def valid(s,p):
 return p['apparent_gender']==s['gender'] and abs(p['apparent_age']-s['age'])<=7 and (not p['uniform'] or bool(set(p['role_tags'])&set(s['role_tags'])))
def cost(s,p):return abs(p['apparent_age']-s['age']) + (0 if p['id']==s['portrait'] else 9) + (3 if p['uniform'] else 0)
cul=[s for s in slots if s['culprit'] and s['case']!='w007']
mat=np.full((len(cul),len(reg)+len(cul)),100000.,dtype=float)
for i,s in enumerate(cul):
 for j,p in enumerate(reg):
  if p['id'] not in reserved and valid(s,p):mat[i,j]=cost(s,p)+j/10000
 mat[i,len(reg)+i]=1000
rows,cols=linear_sum_assignment(mat);assigned={}
for i,j in zip(rows,cols):assigned[(cul[i]['case'],cul[i]['suspect'])]=reg[j]['id'] if j<len(reg) else None
out=[]
for c in sorted({s['case'] for s in slots}):
 group=[s for s in slots if s['case']==c]
 used=[assigned[(s['case'],s['suspect'])] for s in group if s['culprit'] and c!='w007']; used=[x for x in used if x]
 for s in sorted(group,key=lambda x:not x['culprit']):
  if c=='w007':pid=s['portrait']
  elif s['culprit']:pid=assigned[(c,s['suspect'])]
  else:
   choices=[p for p in reg if valid(s,p) and p['id'] not in used and all(frozenset((p['id'],u)) not in close for u in used)]
   pid=min(choices,key=lambda p:(cost(s,p),p['id']))['id'] if choices else None
   if pid:used.append(pid)
  old=by[s['portrait']]; reasons=[]
  if abs(old['apparent_age']-s['age'])>7:reasons.append('age gap >7')
  if old['uniform'] and not set(old['role_tags'])&set(s['role_tags']):reasons.append('unrelated uniform')
  if pid!=s['portrait'] and not reasons:reasons.append('global culprit allocation / within-cast separation')
  out.append({**s,'proposed_portrait':pid,'reason':'; '.join(reasons) or 'retained','status':'outside remap scope' if c=='w007' else ('new portrait needed' if not pid else 'draft; needs cast visual review')})
(O/'mapping-draft.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
with open(O/'before-after-draft.csv','w') as f:
 keys=['case','suspect','name','gender','age','role','portrait','proposed_portrait','reason','status']; w=csv.DictWriter(f,keys,extrasaction='ignore');w.writeheader();w.writerows(out)
print('slots',len(out),'proposed changes',sum(x['proposed_portrait']!=x['portrait'] for x in out),'gaps',sum(not x['proposed_portrait'] for x in out))
for x in out:
 if not x['proposed_portrait']:print('GAP',x['case'],x['suspect'],x['age'],x['gender'],x['role'])
