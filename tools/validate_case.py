#!/usr/bin/env python3
"""Validate a daily case that ChatGPT wrote (second prompt in docs/story-chatgpt-prompt.md).

    python tools/validate_case.py reply.json [--fix-message F] [--autofix OUT] [--warnings] [--strict]
The reply is a normal case JSON plus two kit-only keys: `_notify` {head, body} (the notification teaser) and
`_kit` {puzzle_type, culprit_slot}; the importer removes them. Exit code: 0 pass, 1 fail.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storykit as K  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--fix-message")
    ap.add_argument("--autofix")
    ap.add_argument("--warnings", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--root", default=str(K.ROOT), help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None
    rep, obj, notes = K.check_text(K.read_input(a.file), "case", None, Path(a.root))
    print(K.format_report(rep, obj, "اعتبارسنجی پرونده‌ی شبانه"))
    ok = rep.ok and not (a.strict and rep.warnings)
    if obj is not None and a.autofix:
        fixed, n = K.autofix(obj)
        K.write_json(Path(a.autofix), fixed)
        print(f"\nفایل اصلاح‌شده‌ی نویسه‌ها نوشته شد: {a.autofix} ({K.fa(n)} متن تغییر کرد)")
    if not ok:
        msg = K.build_fix_message(rep, obj, "پرونده", include_warnings=a.warnings or a.strict)
        if msg:
            print("\n──────── پیام اصلاحیه برای چسباندن در ChatGPT ────────\n" + msg + "\n──────────────────────────────────────────────")
            if a.fix_message:
                Path(a.fix_message).write_text(msg + "\n", encoding="utf-8")
    else:
        print("\nمرحله‌ی بعد: تست کور (docs/case-writing-rules.md بخش ۷)، بعد python tools/import_case.py", a.file)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
