#!/usr/bin/env python3
"""Validate and import story chapters as DRAFTS (the story stays closed: STORY_SEASON opens_at is not touched).

    python tools/import_story.py reply.json [--replace] [--dry-run]
    python tools/import_story.py --inbox content_inbox/story      # nightly run: every *.json in the inbox, lowest chapter first

A chapter that passes is repaired (characters only), stripped of the kit-only `_kit` key and written to
server/app/content/story/sNN/chNN.json; its summary/type/culprit go to the season ledger `kit.json` next to it.
Chapters must be imported in order (no gaps: the server refuses to start otherwise).
Inbox mode moves a file to `imported/` (ok) or `rejected/` (with `<name>.اصلاحیه.txt`, the fix message for ChatGPT).
Exit code: 0 = all imported (or nothing to do), 1 = something was rejected. No network, no paid API.
"""
import argparse
import datetime
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storykit as K  # noqa: E402


def gate_status(root: Path) -> str:
    c = K.load_content(root)
    opens = c.STORY_SEASON["opens_at"]
    if opens >= "2090":
        return f"گیت بسته است (opens_at={opens}) ✓"
    return f"⚠ opens_at={opens}: داستان برای بازیکن‌ها باز است! فصل‌های پیش‌نویس همین حالا دیده می‌شوند"


def import_one(raw: str, root: Path, replace=False, dry=False, expect=None):
    """-> (ok, message, fix_message). Writes nothing when anything fails."""
    rep, obj, notes = K.check_text(raw, "story", expect, root)
    if not rep.ok or obj is None:
        return False, K.format_report(rep, obj, "رد شد", show_warnings=False), K.build_fix_message(rep, obj, "فصل")
    ch, season = obj["chapter"], obj["season"]
    sdir = K.story_dir(root) / f"s{season:02d}"
    existing = sorted(int(p.stem[2:]) for p in sdir.glob("ch[0-9][0-9].json"))
    target = sdir / f"ch{ch:02d}.json"
    if ch in existing and not replace:
        return False, f"فصل {K.fa(ch)} از قبل هست ({target.name}); برای جایگزینی --replace بزن", ""
    need = [n for n in range(1, ch) if n not in existing]
    if need:
        return False, f"فصل‌ها باید پشت‌سرهم وارد شوند؛ اول فصل {K.fa(need[0])} را وارد کن (سرور با شماره‌ی جاافتاده بالا نمی‌آید)", ""
    fixed, n_fixed = K.autofix(obj)
    clean = K.strip_meta(fixed)
    # the server's own loader must accept exactly what we write
    content = K.load_content(root)
    content.validate_story(json.loads(json.dumps(clean)), season, ch)
    msg = f"فصل {K.fa(ch)} «{clean['title']}» پذیرفته شد → {target.relative_to(root)} ({K.fa(n_fixed)} متن نویسه‌اصلاح شد، {K.fa(len(rep.warnings))} هشدار)"
    if dry:
        return True, "[آزمایشی، چیزی نوشته نشد] " + msg, ""
    K.write_json(target, clean)
    kp = sdir / "kit.json"
    ledger = K.load_kit(root, season)
    kit = obj["_kit"]
    ledger.setdefault("chapters", {})[str(ch)] = {
        "title": clean["title"], "type": kit["puzzle_type"], "culprit": kit["culprit_slot"],
        "summary": kit["summary"].strip(), "thread": clean["thread"].strip(),
        "imported": datetime.date.today().isoformat(), "blind_test": "pending"}
    ledger["chapters"] = dict(sorted(ledger["chapters"].items(), key=lambda kv: int(kv[0])))
    K.write_json(kp, ledger)
    return True, msg, ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", nargs="?")
    ap.add_argument("--inbox")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--root", default=str(K.ROOT), help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None
    root = Path(a.root)
    if bool(a.file) == bool(a.inbox):
        ap.error("یا یک فایل بده یا --inbox")
    print(gate_status(root))
    bad = 0
    if a.file:
        ok, msg, fix = import_one(K.read_input(a.file), root, a.replace, a.dry_run)
        print(msg)
        if fix:
            print("\n──────── پیام اصلاحیه برای ChatGPT ────────\n" + fix)
        bad = 0 if ok else 1
    else:
        inbox = Path(a.inbox)
        files = []
        for f in sorted(inbox.glob("*.json")):
            m = re.search(r'"id"\s*:\s*"s\d{2}ch(\d{2})"', f.read_text(encoding="utf-8"))
            files.append((int(m.group(1)) if m else 99, f.name, f))
        if not files:
            print("صندوق ورودی خالی است؛ کاری نیست.")
        for _, _, f in sorted(files):
            ok, msg, fix = import_one(f.read_text(encoding="utf-8"), root, a.replace, a.dry_run)
            print(f"{f.name}: {msg}")
            if not a.dry_run:
                dest = inbox / ("imported" if ok else "rejected")
                dest.mkdir(exist_ok=True)
                shutil.move(str(f), dest / f.name)
                if fix:
                    (dest / (f.stem + ".اصلاحیه.txt")).write_text(fix + "\n", encoding="utf-8")
            bad += 0 if ok else 1
    if not a.dry_run:
        print("\nبعدی: تست کور فصل (docs/story-workflow.md) و ثبت نتیجه در docs/story-status.md؛ داستان بسته می‌ماند.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
