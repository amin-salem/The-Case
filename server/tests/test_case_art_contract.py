"""Contract on actual case files; historical defects are reported, never allowlisted."""
import base64
import hashlib
import itertools
import json
import re
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / 'docs/reviews/portrait-quality'

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def cases():
    for mode in ('cases', 'weekly'):
        for path in sorted((ROOT / 'server/app/content' / mode).glob('*.json')):
            yield read(path)

class CaseArtContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = read(ROOT / 'docs/art-registry.json')['portraits']
        cls.reg = {r['id']: r for r in cls.rows}
        cls.approvals = read(ROOT / 'docs/art-role-approvals.json')
        cls.review = read(REVIEW / 'machine-candidates.json')['candidates']

    def test_registry_matches_files_dart_ages_and_bytes(self):
        reg = self.reg
        self.assertEqual(len(self.rows), len(reg))
        folder = ROOT / 'app/assets/portraits'
        self.assertEqual(set(reg), {p.stem for p in folder.glob('*.webp')})
        dart = (ROOT / 'app/lib/widgets/character.dart').read_text()
        block = dart.split('const Set<String> kPortraits = {', 1)[1].split('};', 1)[0]
        self.assertEqual(set(reg), set(re.findall(r"'([^']+)'", block)))
        self.assertEqual({k:v['apparent_age'] for k,v in reg.items()}, read(ROOT/'docs/portrait-ages.json'))
        for k,r in reg.items():
            with self.subTest(portrait=k):
                for field in ('hair_color','hair_style','facial_hair','skin_tone','face_shape','clothing','role_tags'):
                    self.assertTrue(r[field], field)
                self.assertIsInstance(r['glasses'], bool)
                self.assertIsInstance(r['uniform'], bool)
                self.assertIn(r['apparent_gender'], ('m','f'))
                self.assertEqual(r['apparent_age_range'], [r['apparent_age']-5, r['apparent_age']+5])
                self.assertTrue(r['uniform_type'] in r['role_tags'] if r['uniform'] else r['uniform_type'] is None)
                self.assertEqual(r['sha256'], hashlib.sha256((folder/f'{k}.webp').read_bytes()).hexdigest())

    def test_every_lookalike_candidate_has_image_bound_visual_review(self):
        features=read(REVIEW/'fingerprints.json')
        self.assertEqual(set(features),set(self.reg))
        reviewed={(x['a'],x['b']):x for x in self.review}
        expected=set()
        vectors={k:struct.unpack('<576f',base64.b64decode(v['hog_f32le'])) for k,v in features.items()}
        for k,item in features.items():
            self.assertEqual(item['sha256'], self.reg[k]['sha256'])
        for a,b in itertools.combinations(sorted(features),2):
            dist=(int(features[a]['phash'],16)^int(features[b]['phash'],16)).bit_count()
            sim=sum(x*y for x,y in zip(vectors[a],vectors[b]))
            if dist>10 and sim<0.88: continue
            expected.add((a,b))
            row=reviewed[a,b]
            self.assertIn(row['decision'], ('avoid_same_cast','visually_distinguishable'))
            self.assertEqual((row['sha256_a'],row['sha256_b']), (features[a]['sha256'],features[b]['sha256']))
        self.assertEqual(set(reviewed), expected)
        self.assertEqual(len(reviewed),len(self.review))

    def test_all_casts_and_global_culprit_album(self):
        blocked={frozenset(p) for p in read(REVIEW/'editorial-neighbours.json')}
        blocked.update(frozenset((p['a'],p['b'])) for p in self.review if p['decision']=='avoid_same_cast')
        album={}
        for c in cases():
            used=[]
            for s in c['suspects']:
                key=s['avatar']['portrait']
                self.assertIn(key,self.reg)
                self.assertEqual(s['avatar']['gender'], self.reg[key]['apparent_gender'])
                self.assertNotIn(key,used,c['id'])
                self.assertFalse(any(frozenset((key,other)) in blocked for other in used), (c['id'],key,used))
                used.append(key)
                if s['id']==c['solution']['culprit']:
                    self.assertNotIn(key,album,(key,c['id'],album.get(key)))
                    album[key]=c['id']
            self.assertIn(c['id'],album.values())

    def test_all_ages_and_uniforms(self):
        errors=[]
        for c in cases():
            for s in c['suspects']:
                r=self.reg[s['avatar']['portrait']]
                slot=f"{c['id']}/{s['id']}"
                if abs(s['age']-r['apparent_age'])>7:errors.append(f"{slot}: age {s['age']} vs {r['apparent_age']}")
                if r['uniform']:
                    approval=self.approvals.get(slot,{})
                    if approval.get('role')!=s['role'] or not set(approval.get('role_tags',[])).intersection(r['role_tags']):
                        errors.append(f"{slot}: {r['uniform_type']} incompatible with {s['role']}")
        self.assertEqual(errors, [], '\n'.join(errors))

if __name__=='__main__': unittest.main()
