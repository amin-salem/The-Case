"""Repository assets must cover every mode, including unpublished weekend cases."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CaseArtContractTests(unittest.TestCase):
    def test_every_case_portrait_and_scene_is_shipped_and_registered(self):
        portraits = {p.stem for p in (ROOT / 'app/assets/portraits').glob('*.webp')}
        scenes = {p.stem for p in (ROOT / 'app/assets/scenes').glob('*.webp')}
        dart = (ROOT / 'app/lib/widgets/character.dart').read_text()
        block = dart.split('const Set<String> kPortraits = {', 1)[1].split('};', 1)[0]
        registered = set(re.findall(r"'([^']+)'", block))
        self.assertEqual(portraits, registered, 'Dart registry and packaged portraits differ')
        scene_dart = (ROOT / 'app/lib/widgets/scene.dart').read_text()
        scene_block = scene_dart.split('const Set<String> kSceneArt = {', 1)[1].split('};', 1)[0]
        self.assertEqual(scenes, set(re.findall(r"'([^']+)'", scene_block)))
        ages = json.loads((ROOT / 'docs/portrait-ages.json').read_text())
        self.assertEqual(portraits, set(ages))
        pubspec = (ROOT / 'app/pubspec.yaml').read_text()
        self.assertIn('- assets/portraits/', pubspec)
        self.assertIn('- assets/scenes/', pubspec)
        count = 0
        for mode in ('cases', 'weekly', 'story'):
            files = sorted((ROOT / 'server/app/content' / mode).rglob('*.json'))
            self.assertTrue(files, mode)
            for path in files:
                data = json.loads(path.read_text())
                if 'suspects' not in data:
                    continue  # Other story formats have their own scene assets.
                with self.subTest(case=path.name):
                    self.assertIn(data['scene'], scenes)
                    used = []
                    for suspect in data['suspects']:
                        portrait = suspect.get('avatar', {}).get('portrait')
                        self.assertIn(portrait, portraits, f"{path.name}/{suspect['id']}: {portrait}")
                        used.append(portrait)
                        count += 1
                    self.assertEqual(len(used), len(set(used)), f'{path.name}: duplicate faces in one cast')
        self.assertGreater(count, 0)


if __name__ == '__main__':
    unittest.main()
