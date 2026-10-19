import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest

from app import content
from app.content_paths import CONTENT_ROOT, content_root
from app.config import get_settings
from tools.unpublished_content import unpublished

ROOT = Path(__file__).resolve().parents[1]
TEHRAN = ZoneInfo("Asia/Tehran")


def test_default_root_preserves_all_loaders(monkeypatch):
    monkeypatch.setattr(get_settings(), "content_dir", "")
    assert content_root() == ROOT / "app/content"
    assert content.CASES_DIR == CONTENT_ROOT / "cases"
    assert content.WEEKLY_DIR == CONTENT_ROOT / "weekly"
    assert content.STORY_DIR == CONTENT_ROOT / "story"
    assert content.all_cases() and content.weekly_cases()


def test_external_bundle_is_used_by_every_runtime_loader(tmp_path):
    bundle = tmp_path / "private"
    shutil.copytree(ROOT / "app/content", bundle)
    first = next((bundle / "cases").glob("*.json"))
    data = json.loads(first.read_text(encoding="utf-8"))
    data["title"] = "external bundle marker"
    first.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    (bundle / "notify.json").write_text('{"external_marker": true}', encoding="utf-8")
    code = """
import json
from app import content, riddles
from app.content_paths import CONTENT_ROOT
assert content.CASES_DIR == CONTENT_ROOT / 'cases'
assert content.WEEKLY_DIR == CONTENT_ROOT / 'weekly'
assert content.STORY_DIR == CONTENT_ROOT / 'story'
assert riddles.PATH == CONTENT_ROOT / 'riddles.json'
assert any(c.data['title'] == 'external bundle marker' for c in content.all_cases())
assert content.weekly_cases() and content.story_chapters()
assert riddles.all_riddles()
assert content._notify_texts() == {'external_marker': True}
print('external loaders ok')
"""
    r = subprocess.run([sys.executable, "-c", code], cwd=ROOT, env={**os.environ, "CONTENT_DIR": str(bundle)},
                       text=True, capture_output=True)
    assert r.returncode == 0, r.stderr


def test_explicit_incomplete_bundle_never_falls_back(tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "content_dir", str(tmp_path))
    with pytest.raises(ValueError, match="CONTENT_DIR"):
        content_root()


def test_inventory_uses_open_hour_and_weekend_chapter_boundaries(monkeypatch):
    nightly = content.by_id("c020")
    at = content.opens_at(nightly)
    weekend = SimpleNamespace(id="w-test", publish=nightly.publish, data={
        "open_hour": at.hour, "chapters": [{"at_hours": 0}, {"at_hours": 12}],
        "solution": {"culprit": "SECRET_CULPRIT"}, "title": "SECRET_PROSE"})
    monkeypatch.setattr(content, "all_cases", lambda: [nightly])
    monkeypatch.setattr(content, "weekly_cases", lambda: [weekend])
    monkeypatch.setattr(content, "_story_load", lambda _: {})
    before = unpublished(at - timedelta(microseconds=1))
    assert {r["kind"] for r in before} == {"nightly", "weekend", "weekend_chapter"}
    exact = unpublished(at.astimezone(ZoneInfo("UTC")))
    assert exact == [{"kind": "weekend_chapter", "id": "w-test", "opens_at": (at + timedelta(hours=12)).isoformat(), "chapter": 2}]
    assert unpublished(at + timedelta(hours=12)) == []
    output = json.dumps(before)
    assert "SECRET" not in output and "culprit" not in output and "solution" not in output and "title" not in output


def test_story_inventory_uses_season_gate_not_placeholder_publish(monkeypatch):
    at = datetime(2099, 1, 1, tzinfo=TEHRAN)
    chapter = SimpleNamespace(id="s01ch01", number=1, publish=datetime(2026, 1, 1).date())
    monkeypatch.setattr(content, "all_cases", lambda: [])
    monkeypatch.setattr(content, "weekly_cases", lambda: [])
    monkeypatch.setattr(content, "_story_load", lambda _: {1: [chapter], 2: [SimpleNamespace(id="s02ch01", number=1)]})
    monkeypatch.setattr(content, "story_opens_at", lambda: at)
    assert len(unpublished(at - timedelta(seconds=1))) == 2
    assert unpublished(at) == [{"kind": "story_chapter", "id": "s02ch01", "opens_at": None, "chapter": 1, "reason": "season_not_scheduled"}]
    with pytest.raises(ValueError):
        unpublished(datetime(2026, 1, 1))
