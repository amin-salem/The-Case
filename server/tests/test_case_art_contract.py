"""Contract on actual cases; only explicitly dated pending remaps may wait."""
import base64
import hashlib
import itertools
import json
import re
import struct
import unittest
import sys
from datetime import datetime, date
from zoneinfo import ZoneInfo
from unittest.mock import patch
import pytest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from art_rules import age_band, incompatibilities, available, head_covering_errors, pending_remap_deadline  # noqa: E402
REVIEW = ROOT / 'docs/reviews/portrait-quality'

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def cases():
    for mode in ('cases', 'weekly'):
        for path in sorted((ROOT / 'server/app/content' / mode).glob('*.json')):
            yield read(path)


def review_today():
    return datetime.now(ZoneInfo('Asia/Tehran')).date()

class CaseArtContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = read(ROOT / 'docs/art-registry.json')['portraits']
        cls.reg = {r['id']: r for r in cls.rows}
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
                self.assertIs(type(r['apparent_age']), int)
                self.assertEqual(r['age_band'], age_band(r['apparent_age']))
                self.assertTrue(r['facial_expression'])
                self.assertIn(r['clothing_formality'], ('everyday','formal'))
                self.assertTrue(r['roles_ok'])
                self.assertIsInstance(r['roles_not_ok'], list)
                self.assertIsInstance(r['restrictions'], list)
                if r['uniform']:
                    self.assertNotIn('*',r['roles_ok'])
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

    def test_distinct_casts_preserve_gender(self):
        blocked={frozenset(p) for p in read(REVIEW/'editorial-neighbours.json')}
        blocked.update(frozenset((p['a'],p['b'])) for p in self.review if p['decision']=='avoid_same_cast')
        for c in cases():
            used=[]
            for s in c['suspects']:
                key=s['avatar']['portrait']
                self.assertIn(key,self.reg)
                self.assertEqual(s['avatar']['gender'], self.reg[key]['apparent_gender'])
                self.assertNotIn(key,used,c['id'])
                self.assertFalse(any(frozenset((key,other)) in blocked for other in used), (c['id'],key,used))
                used.append(key)

    def test_culprit_album_is_unique_without_exceptions(self):
        album={}
        for c in cases():
            suspect=next(s for s in c['suspects'] if s['id']==c['solution']['culprit'])
            key=suspect['avatar']['portrait']
            self.assertIn(key,self.reg)
            self.assertNotIn(key,album,(key,c['id'],album.get(key)))
            album[key]=c['id']

    def test_no_unreleased_portrait_leaks_to_an_old_case(self):
        ledger=read(ROOT/'docs/portrait-release.json')
        releases=ledger['portraits']
        staged={k for k,v in releases.items() if v.get('first_build') is None}
        for c in cases():
            for s in c['suspects']:
                self.assertNotIn(s['avatar']['portrait'],staged,(c['id'],s['id']))
                if c['publish'] >= ledger['check_from']:
                    self.assertTrue(available(s['avatar']['portrait'],c,ledger), (c['id'],s['id']))

    def test_all_ages_and_uniforms(self):
        pending=read(ROOT/'docs/reviews/art-finish/pending-remap.json')
        rows={r['slot']:r for r in pending['remaps']}
        self.assertEqual(len(rows),len(pending['remaps']))
        releases=read(ROOT/'docs/portrait-release.json')['portraits']
        today=review_today()
        failures=[]
        waiting=[]
        for c in cases():
            for s in c['suspects']:
                r=self.reg[s['avatar']['portrait']]
                slot=f"{c['id']}/{s['id']}"
                reasons=incompatibilities(r,s)
                if not reasons:
                    continue
                detail=f"{slot}: {', '.join(reasons)}; character age {s['age']}, portrait {r['id']} age {r['apparent_age']}; {s['role']}"
                row=rows.get(slot)
                if not row or row['current_portrait']!=r['id'] or not set(reasons)<={'age','role/clothing'}:
                    failures.append(detail)
                    continue
                try:
                    deadline=pending_remap_deadline(row,releases[row['replacement_portrait']])
                except (KeyError,TypeError,ValueError) as exc:
                    failures.append(f'{detail}; invalid pending date: {exc}')
                    continue
                if today>=deadline:
                    failures.append(f'{detail}; pending expired / usable_from reached: {deadline}')
                else:
                    waiting.append(f"{slot} → {row['replacement_portrait']}؛ تا {deadline}")
        self.assertEqual(failures,[], '\n'.join(failures))
        if waiting:
            count=str(len(waiting)).translate(str.maketrans('0123456789','۰۱۲۳۴۵۶۷۸۹'))
            pytest.skip(f"در انتظار: {count} جایگاه؛ مهلت‌ها به وقت تهران؛ این وضعیت مجوز استفاده از تصویر نیست. " + ' | '.join(waiting))

    def test_pending_window_expires_on_the_day_and_never_hides_other_errors(self):
        row={'reviewed_on':'2026-11-11','waiting_until':'2026-11-25','allowed_from':None}
        for release,expected in (({'usable_from':None},'2026-11-25'),
                                 ({'usable_from':'2026-11-19'},'2026-11-19'),
                                 ({'usable_from':'2026-12-01'},'2026-11-25')):
            self.assertEqual(pending_remap_deadline(row,release),date.fromisoformat(expected))
        for value in (None,'','2099-01-01','2026-11-11'):
            with self.assertRaises((KeyError,TypeError,ValueError)):
                pending_remap_deadline(dict(row,waiting_until=value),{})
        fixture={'id':'fixture','suspects':[{'id':'s1','age':40,'role':'fixture',
                 'avatar':{'gender':'m','portrait':'old'}}]}
        entry=dict(row,slot='fixture/s1',current_portrait='old',replacement_portrait='new')
        def exercise(day,usable=None,entries=None,reason=None):
            def fixture_read(path):
                if path==ROOT/'docs/reviews/art-finish/pending-remap.json':
                    return {'remaps':[entry] if entries is None else entries}
                return {'portraits':{'new':{'usable_from':usable}}}
            with patch(f'{__name__}.read',side_effect=fixture_read), \
                 patch(f'{__name__}.cases',return_value=[fixture]), \
                 patch(f'{__name__}.review_today',return_value=day), \
                 patch(f'{__name__}.incompatibilities',return_value=['age'] if reason is None else reason), \
                 patch.object(self,'reg',{'old':{'id':'old','apparent_age':80}}):
                self.test_all_ages_and_uniforms()
        # Before the boundary it really calls pytest.skip; on/after it fails.
        with patch.object(pytest,'skip',side_effect=RuntimeError('waiting fixture')) as skip:
            with self.assertRaisesRegex(RuntimeError,'waiting fixture'):
                exercise(date(2026,11,24))
            self.assertIn('fixture/s1',skip.call_args.args[0])
            self.assertIn('2026-11-25',skip.call_args.args[0])
        for day in (date(2026,11,25),date(2026,11,26)):
            with self.assertRaises(AssertionError):
                exercise(day)
        # An earlier usable_from ends the wait immediately, not tomorrow.
        with self.assertRaises(AssertionError):
            exercise(date(2026,11,12),usable='2026-11-12')
        # Unlisted, undated and non-age/role defects cannot be skipped.
        for entries,reason in (([],None),([dict(entry,waiting_until=None)],None),(None,['gender'])):
            with self.assertRaises(AssertionError):
                exercise(date(2026,11,11),entries=entries,reason=reason)

    def test_staged_assets_have_dimensions_budget_and_blocking_date(self):
        releases=read(ROOT/'docs/portrait-release.json')['portraits']
        for key,release in releases.items():
            if release.get('first_build') is not None:
                continue
            self.assertIn(release['usable_from'], (None, '9999-12-31'))
            self.assertEqual(self.reg[key]['usable_from'],release['usable_from'])
            self.assertFalse(available(key, {'publish':'9999-12-31'}, {'portraits':releases}))
            data=(ROOT/'app/assets/portraits'/f'{key}.webp').read_bytes()
            self.assertLessEqual(len(data),18000,key)
            self.assertEqual(data[:4],b'RIFF')
            self.assertEqual(data[8:12],b'WEBP')
            pos=12;dims=None
            while pos+8 <= len(data):
                tag=data[pos:pos+4];size=int.from_bytes(data[pos+4:pos+8],'little');body=data[pos+8:pos+8+size]
                if tag==b'VP8X':dims=(int.from_bytes(body[4:7],'little')+1,int.from_bytes(body[7:10],'little')+1)
                elif tag==b'VP8 ' and dims is None:dims=tuple(v & 0x3fff for v in struct.unpack('<HH',body[6:10]))
                elif tag==b'VP8L' and dims is None:
                    value=int.from_bytes(body[1:5],'little');dims=((value & 0x3fff)+1,((value>>14)&0x3fff)+1)
                pos+=8+size+(size%2)
            self.assertEqual(dims,(448,448),key)

    def test_unconfirmed_release_never_grants_access(self):
        for build,day in ((None,None),(None,'2000-01-01'),(99,None),(99,'')):
            ledger={'portraits':{'fixture':{'first_build':build,'usable_from':day}}}
            self.assertFalse(available('fixture', {'publish':'2099-01-01'}, ledger, 'fixture'))

    def test_pending_remaps_are_compatible_unique_and_not_live(self):
        plan=read(ROOT/'docs/reviews/art-finish/pending-remap.json')
        actual={f"{c['id']}/{s['id']}" for c in cases() for s in c['suspects']
                if incompatibilities(self.reg[s['avatar']['portrait']],s)}
        self.assertEqual({r['slot'] for r in plan['remaps']},actual)
        self.assertEqual(len(plan['remaps']),len(actual))
        ledger=read(ROOT/'docs/portrait-release.json')
        blocked={frozenset(p) for p in read(REVIEW/'editorial-neighbours.json')}
        blocked.update(frozenset((p['a'],p['b'])) for p in self.review if p['decision']=='avoid_same_cast')
        indexed={c['id']:c for c in cases()}
        album={next(s for s in c['suspects'] if s['id']==c['solution']['culprit'])['avatar']['portrait'] for c in cases()}
        replacements=set()
        for row in plan['remaps']:
            c=indexed[row['case_id']]
            s=next(s for s in c['suspects'] if s['id']==row['suspect_id'])
            key=row['replacement_portrait']
            self.assertEqual(row['slot'],f"{c['id']}/{s['id']}")
            self.assertEqual(s['avatar']['portrait'],row['current_portrait'])
            self.assertEqual(incompatibilities(self.reg[key],s),[])
            self.assertNotIn(key,album)
            self.assertNotIn(key,replacements)
            replacements.add(key)
            self.assertEqual(row['reviewed_on'],'2026-11-11')
            self.assertEqual(row['waiting_until'],'2026-11-25')
            pending_remap_deadline(row,ledger['portraits'][key])
            self.assertFalse(available(key,c,ledger))
            self.assertNotIn(key,{a['avatar']['portrait'] for a in c['suspects']})
            self.assertFalse(any(frozenset((key,a['avatar']['portrait'])) in blocked
                                 for a in c['suspects'] if a['id']!=s['id']))

    def test_cosmetic_aliases_reference_one_existing_asset(self):
        rows=read(ROOT/'docs/art-registry.json')['cosmetics']
        aliases={}
        for r in rows:
            data=(ROOT/r['path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(),r['sha256'])
            for alias in r['aliases']:
                self.assertNotIn(alias,aliases)
                aliases[alias]=r['id']
            if not r['existing_main']:
                self.assertLessEqual(len(data),18000 if r['kind']=='avatars' else 40000,r['id'])
        self.assertEqual(len(aliases),13)

    def test_every_female_asset_has_allowed_head_covering(self):
        registry=read(ROOT/'docs/art-registry.json')
        rows=registry['portraits']+registry['cosmetics']
        cosmetics=registry['cosmetics']
        self.assertEqual({r['path'] for r in cosmetics}, {
            str(p.relative_to(ROOT)) for folder in ('avatars','frames')
            for p in (ROOT/'app/assets'/folder).glob('*.webp')
        })
        errors=[]
        for row in rows:
            self.assertIn(row['apparent_gender'], ('m','f','none','unspecified'),row['id'])
            errors.extend(head_covering_errors(row))
        self.assertEqual(errors, [], '\n'.join(errors))

    def test_head_covering_gate_rejects_missing_uncovered_and_invalid_values(self):
        for value in (None,'','uncovered','short_hair','hat','hijab',False):
            with self.subTest(value=value):
                self.assertTrue(head_covering_errors({'id':'fixture','apparent_gender':'f','head_covering':value}))
        self.assertTrue(head_covering_errors({'id':'missing','apparent_gender':'f'}))
        for value in ('scarf','scarf_hair_visible'):
            self.assertEqual(head_covering_errors({'id':'fixture','apparent_gender':'f','head_covering':value}),[])

    def test_staged_women_are_covered_and_wear_neutral_clothes(self):
        releases=read(ROOT/'docs/portrait-release.json')['portraits']
        for row in self.rows:
            if row['apparent_gender']!='f' or row['id'] not in releases or releases[row['id']]['first_build'] is not None:
                continue
            with self.subTest(portrait=row['id']):
                self.assertEqual(head_covering_errors(row),[])
                self.assertFalse(row['uniform'])
                self.assertEqual(row['clothing_formality'],'everyday')

    def test_head_covering_review_is_bound_to_the_actual_image(self):
        registry=read(ROOT/'docs/art-registry.json')
        women={r['path']:r for r in registry['portraits']+registry['cosmetics'] if r['apparent_gender']=='f'}
        review={r['path']:r for r in registry['head_covering_visual_audit']}
        self.assertEqual(set(women),set(review))
        for path,row in women.items():
            self.assertEqual(review[path]['head_covering'],row['head_covering'])
            self.assertEqual(review[path]['sha256'],hashlib.sha256((ROOT/path).read_bytes()).hexdigest())

if __name__=='__main__': unittest.main()
