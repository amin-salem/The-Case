#!/usr/bin/env python3
"""Validate a story chapter that ChatGPT wrote (docs/story-workflow.md). Offline, free, deterministic.

    python tools/validate_story.py reply.json            # file with ChatGPT's reply (fences / extra text are tolerated)
    python tools/validate_story.py - < reply.json        # from stdin
    options: --chapter N         the chapter you asked for (checks the id)
             --fix-message F     write the ready «اصلاحیه» message for ChatGPT to F (also printed)
             --autofix OUT       write the JSON with Arabic letters / digits / spaces repaired
             --warnings          also put non-automatic warnings into the fix message
             --strict            warnings fail too
Exit code: 0 = pass, 1 = fail.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storykit as K  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--chapter", type=int)
    ap.add_argument("--fix-message")
    ap.add_argument("--autofix")
    ap.add_argument("--warnings", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--root", default=str(K.ROOT), help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None
    root = Path(a.root)
    rep, obj, notes = K.check_text(K.read_input(a.file), "story", a.chapter, root)
    title = f"اعتبارسنجی فصل {K.fa(obj.get('chapter', a.chapter or '؟'))}" if isinstance(obj, dict) else "اعتبارسنجی فصل"
    print(K.format_report(rep, obj, title))
    ok = rep.ok and not (a.strict and rep.warnings)
    if obj is not None and a.autofix:
        fixed, n = K.autofix(obj)
        K.write_json(Path(a.autofix), fixed)
        print(f"\nفایل اصلاح‌شده‌ی نویسه‌ها نوشته شد: {a.autofix} ({K.fa(n)} متن تغییر کرد)")
    if not ok:
        msg = K.build_fix_message(rep, obj, "فصل", include_warnings=a.warnings or a.strict)
        if msg:
            print("\n──────── پیام اصلاحیه برای چسباندن در ChatGPT ────────\n" + msg + "\n──────────────────────────────────────────────")
            if a.fix_message:
                Path(a.fix_message).write_text(msg + "\n", encoding="utf-8")
    elif obj is not None:
        print("\n──────── خلاصه برای پیام «فصل بعد» ────────\n" + K.next_context(obj))
        print("\nمرحله‌ی بعد: python tools/import_story.py", a.file)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
