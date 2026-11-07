import json,re,csv,hashlib,collections
from pathlib import Path
from PIL import Image
R=Path(__file__).parent; O=R/'docs/reviews/portrait-pool';O.mkdir(parents=True,exist_ok=True)
cs=[json.load(open(p)) for p in sorted((R/'server/app/content').glob('*/*.json'))]
selected=[c for c in cs if 'c038'<=c['id']<='c062' or 'w001'<=c['id']<='w006']
ages=json.load(open(R/'docs/portrait-ages.json'));pool={p.stem:p for p in (R/'app/assets/portraits').glob('*.webp')}
reg=set(re.findall("'([^']+)'",(R/'app/lib/widgets/character.dart').read_text().split('const Set<String> kPortraits = {')[1].split('};')[0]))
rows=[];reuses=collections.defaultdict(list);culprits=collections.defaultdict(list);scenes=collections.defaultdict(list);missing=[]
for c in cs:
 for s in c['suspects']:
  p=s['avatar'].get('portrait','');reuses[p].append(c['id']+'/'+s['id'])
  if s['id']==c['solution']['culprit']:culprits[p].append(c['id'])
for c in selected:
 scenes[c['scene']].append(c['id'])
 for s in c['suspects']:
  a=s['avatar'];p=a.get('portrait','');delta=abs(ages[p]-s['age']) if p in ages else None
  row=dict(case=c['id'],suspect=s['id'],name=s['name'],role=s['role'],age=s['age'],gender=a['gender'],portrait=p,file_exists=p in pool,registered=p in reg,metadata_age=ages.get(p),age_difference=delta,gender_key_matches=p.startswith(a['gender']+'_'),age_review=delta is not None and delta>10,all_case_uses=';'.join(reuses[p]))
  rows.append(row)
  if p not in pool:missing.append(row)
with open(O/'current-cast.csv','w') as f:
 w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
# Future entries are anonymous slots, never bound to names. Gender is an editorial
# assumption from the outline, not a face classification. U means ambiguous.
genders=['fmfmf','mfmmf','fmfmf','mfmmf','fmfmm','mfmfm','mffmm','mf mfm'.replace(' ',''),'fmmfm','fmffm','fmfmf','fmfmf','fmfmf','mfmfm','fmfmf','fmfmm','mfmfm','mfmff','mfmfm','fmfmu','mfmfm','mfmfm','fmfmm','fmfmf','mfmfm','fmfmm','fmfmf','fmfmf','fmfmf','fmmfm','fmmfmfmm','fmfmfmfm','fmfmmfmm','fmffmmfm','fmfmmmfm','fmfmfmfu']
slots=[]
for i,b in enumerate((R/'ideas.md').read_text().split('### ')[1:],1):
 line=next(x for x in b.splitlines() if x.startswith('- مظنون'))
 entries=line.split(':',1)[1].split('؛')[:5 if i<=30 else 8]
 assert len(entries)==len(genders[i-1]),i
 cid=f'c{i+52:03}' if i<=30 else f'w{i-24:03}'
 for j,e in enumerate(entries):
  parts=[x.strip() for x in e.split('،')];idx=next(k for k,x in enumerate(parts) if re.fullmatch(r'[۰-۹0-9]+(?:←[۰-۹0-9]+)?',x));age=int(parts[idx].split('←')[-1]);role=parts[1] if idx==2 else parts[2];role=role.split(' و ')[0]
  slots.append(dict(idea=i,case=cid,slot=j+1,gender=genders[i-1][j],age=age,age_band='18-35' if age<=35 else '36-54' if age<=54 else '55+',role=role,written=any(c['id']==cid for c in cs)))
with open(O/'future-slots.csv','w') as f:
 w=csv.DictWriter(f,fieldnames=slots[0]);w.writeheader();w.writerows(slots)
counts=collections.Counter((s['gender'],s['age_band'],s['role']) for s in slots if not s['written'])
with open(O/'future-new-face-budget.csv','w') as f:
 w=csv.writer(f);w.writerow(['gender','age_band','role','dedicated_new_faces_upper_budget']);w.writerows([(*k,n) for k,n in sorted(counts.items())])
assert len(slots)==198
hashes=collections.defaultdict(list);dims=collections.Counter()
for p in list(pool.values())+list((R/'app/assets/scenes').glob('*.webp')):
 hashes[hashlib.sha256(p.read_bytes()).hexdigest()].append(p.name)
 with Image.open(p) as im:im.load();dims[str(im.size)]+=1
summary=dict(base='1db49849ade2a9de7510d39069dc0ffe94be585b',cases=len(selected),appearances=len(rows),pool=len(pool),scenes=20,missing=missing,age_differences_over_10=sum(r['age_review'] for r in rows),registry_difference=sorted(reg^set(pool)),age_registry_difference=sorted(set(ages)^set(pool)),gender_key_mismatches=[r for r in rows if not r['gender_key_matches']],within_case_duplicates=[c['id'] for c in cs if len({s['avatar'].get('portrait') for s in c['suspects']})!=len(c['suspects'])],repeated_culprit_ids={p:v for p,v in culprits.items() if len(v)>1},all_repeated_portraits={p:v for p,v in reuses.items() if len(v)>1},scenes_in_scope=dict(scenes),byte_identical_groups=[v for v in hashes.values() if len(v)>1],decoded_dimensions=dict(dims),future_slots=len(slots),unwritten_slots=sum(not s['written'] for s in slots),unwritten_gender_age_counts={str(k):n for k,n in collections.Counter((s['gender'],s['age_band']) for s in slots if not s['written']).items()})
(O/'inventory.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in summary.items() if k not in ['all_repeated_portraits','missing']},ensure_ascii=False,indent=2))
