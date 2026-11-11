"""The same public scene art is used by the case and its archive card."""
import json
import unittest
from pathlib import Path
from datetime import date
from app import content

class SceneVariants(unittest.TestCase):
    def test_backwards_compatibility_and_public_output(self):
        for cid, variant in [('c020','clock'), ('c040','clock'), ('c058','apartment'), ('c001',None)]:
            data=json.loads((content.CASES_DIR/f'{cid}.json').read_text())
            content.validate(data)
            case=content.Case(cid,data['number'],date.fromisoformat(data['publish']),data)
            for payload in (case.summary(), case.public()):
                self.assertEqual(payload.get('scene_variant'),variant)
                self.assertEqual('scene_variant' in payload,variant is not None)
                self.assertEqual(payload['scene'],data['scene'])
                self.assertNotIn('solution',payload)
    def test_unknown_unsafe_and_wrong_base(self):
        original=json.loads((content.CASES_DIR/'c020.json').read_text())
        for scene,v in [('tower','../clock'),('tower',None),('tower','missing'),('tower',[]),('museum','clock')]:
            with self.subTest(scene=scene,v=v), self.assertRaises(content.CaseError):
                content.validate(dict(original,scene=scene,scene_variant=v))
    def test_every_allowed_pair_ships(self):
        assets=Path(__file__).resolve().parents[2]/'app/assets/scenes'
        for base,variants in content.SCENE_VARIANTS.items():
            for v in variants:
                self.assertTrue((assets/f'{base}_{v}.webp').is_file())
