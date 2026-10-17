#!/usr/bin/env python3
"""Validate and import a daily case written by ChatGPT.

    python tools/import_case.py reply.json [--replace] [--dry-run]

Writes server/app/content/cases/cNNN.json (without the kit-only `_kit`/`_notify`) and merges the notification teaser
into server/app/content/notify.json. A case file goes live on its `publish` day once the server is deployed, so run the
blind test (docs/case-writing-rules.md section 7) BEFORE importing and add the line to docs/case-log.md yourself.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storykit as K  # noqa: E402


def import_case(raw: str, root: Path, replace=False, dry=False):
    rep, obj, notes = K.check_text(raw, "case", None, root)
    if not rep.ok or obj is None:
        return False, K.format_report(rep, obj, "رد شد", show_warnings=False), K.build_fix_message(rep, obj, "پرونده")
    target = K.cases_dir(root) / f"{obj['id']}.json"
    if target.exists() and not replace:
        return False, f"{obj['id']} از قبل هست؛ برای جایگزینی --replace بزن", ""
    taken = [c.stem for c in K.cases_dir(root).glob("c*.json") if json.loads(c.read_text(encoding="utf-8")).get("publish") == obj["publish"] and c.stem != obj["id"]]
    if taken and not replace:
        return False, f"روز {obj['publish']} را پرونده‌ی {taken[0]} گرفته است؛ تاریخ دیگری بگذار", ""
    fixed, n_fixed = K.autofix(obj)
    notify = fixed["_notify"]
    clean = K.strip_meta(fixed)
    msg = f"{clean['id']} «{clean['title']}» پذیرفته شد → {target.relative_to(root)} (انتشار {clean['publish']}، {K.fa(n_fixed)} متن نویسه‌اصلاح شد)"
    if dry:
        return True, "[آزمایشی، چیزی نوشته نشد] " + msg, ""
    K.write_json(target, clean)
    nf = K.cases_dir(root).parent / "notify.json"
    table = json.loads(nf.read_text(encoding="utf-8")) if nf.is_file() else {}
    table[clean["id"]] = {"title": clean["title"], "head": notify["head"].strip(), "body": notify["body"].strip()}
    K.write_json(nf, dict(sorted(table.items())), newline=False)  # the file has no final newline
    return True, msg, ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--root", default=str(K.ROOT), help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None
    ok, msg, fix = import_case(K.read_input(a.file), Path(a.root), a.replace, a.dry_run)
    print(msg)
    if fix:
        print("\n──────── پیام اصلاحیه برای ChatGPT ────────\n" + fix)
    if ok and not a.dry_run:
        print("\nبعدی: خط پرونده را به docs/case-log.md اضافه کن (نوع معما + نتیجه‌ی تست کور) و CI را روی شاخه ببین.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
