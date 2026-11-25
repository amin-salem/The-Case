"""Compact index of every case, so a writer can see what exists WITHOUT reading 80 case files.

    python3 server/tools/case_index.py            # rewrite docs/case-index.md and docs/case-names.md
    python3 server/tools/case_index.py --check    # exit 1 if the two files are out of date (not run by CI on purpose)
    python3 server/tools/case_index.py --find علی # which cases use this first name or surname
    python3 server/tools/case_index.py --next     # next free nightly / weekend slot (id, number, publish date)

Pure standard library: it reads the JSON files and the table in docs/case-log.md, so it runs on any machine
(no pydantic, no server stack). It never prints a solution, a hint or a clue text, only metadata and names.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "server" / "app" / "content"
DOCS = ROOT / "docs"
INDEX = DOCS / "case-index.md"
NAMES = DOCS / "case-names.md"

PUNCT = "«»()،,؛;:.؟?!"


def _load(folder: Path, pattern: str) -> list[dict]:
    out = []
    for f in sorted(folder.glob(pattern)):
        d = json.loads(f.read_text(encoding="utf-8"))
        d["_file"] = f.name
        out.append(d)
    return out


def nightly() -> list[dict]:
    return _load(CONTENT / "cases", "c*.json")


def weekend() -> list[dict]:
    return _load(CONTENT / "weekly", "w*.json")


def story() -> list[dict]:
    out: list[dict] = []
    root = CONTENT / "story"
    if root.is_dir():
        for sub in sorted(p for p in root.iterdir() if p.is_dir()):
            out += _load(sub, "*ch*.json")
    return out


def log_types() -> dict[str, str]:
    """case id -> the 'main puzzle type' cell of the newest row for it in docs/case-log.md (best effort)."""
    types: dict[str, str] = {}
    path = DOCS / "case-log.md"
    if not path.exists():
        return types
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\|\s*([cw]\d{3}|s\d\dch\d\d)\b", line)
        if not m:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[2] and cells[2] != "type":
            types[m.group(1)] = re.sub(r"\s+", " ", cells[2])[:90]
    return types


def _culprit(d: dict) -> dict | None:
    cid = (d.get("solution") or {}).get("culprit")
    return next((s for s in d.get("suspects", []) if s["id"] == cid), None)


def _row(d: dict, types: dict[str, str]) -> str:
    c = _culprit(d) or {}
    portrait = (c.get("avatar") or {}).get("portrait") or "-"
    return " | ".join([
        d["id"], str(d.get("publish", "-")), str(d.get("difficulty", "-")), d.get("scene", "-"), d.get("category", "-"),
        d.get("title", "-"), f'{(d.get("solution") or {}).get("culprit", "-")} {c.get("name", "-")} ({c.get("role", "-")})',
        portrait, str(len(d.get("suspects", []))), str(len(d.get("evidence", []))), types.get(d["id"], "-"),
    ])


HEAD = "id | publish | diff | scene | category | title | culprit (slot name role) | culprit portrait | suspects | cards | puzzle type (case-log)"


def build_index() -> str:
    types = log_types()
    n, w, s = nightly(), weekend(), story()
    lines = [
        "# Case index (GENERATED, do not edit by hand)",
        "",
        "Run `python3 server/tools/case_index.py` after adding or changing a case. One line per case: use it to pick a scene, category,",
        "puzzle type, culprit slot and portrait that the last cases did NOT use, and to find the next free slot. It carries no clue text",
        "and no solution. Names are in `docs/case-names.md`.",
        "",
        f"Nightly cases: {len(n)} (last: {n[-1]['id']} published {n[-1]['publish']}). Weekend cases: {len(w)} "
        f"(last: {w[-1]['id']} published {w[-1]['publish']}). Story chapters: {len(s)}.",
        "",
        "## Nightly", "", HEAD, "---|---|---|---|---|---|---|---|---|---|---",
    ]
    lines += [_row(d, types) for d in n]
    lines += ["", "## Weekend", "", HEAD, "---|---|---|---|---|---|---|---|---|---|---"]
    lines += [_row(d, types) for d in w]
    lines += ["", "## Story chapters", ""]
    lines += [f'{d["id"]} | {d.get("title", "-")} | {d.get("scene", "-")} | {d.get("category", "-")}' for d in s] or ["(none)"]
    # the last ten nightly cases at a glance: what the next one must differ from
    last = n[-10:]
    lines += ["", "## Last ten nightly cases (a new case differs from all of these)", ""]
    lines += [f'- {d["id"]}: scene {d.get("scene")}, category {d.get("category")}, culprit slot {(d.get("solution") or {}).get("culprit")}, '
              f'type: {types.get(d["id"], "-")}' for d in last]
    from collections import Counter
    lines += ["", "## Counts", "",
              "scenes: " + ", ".join(f"{k} {v}" for k, v in sorted(Counter(d.get("scene") for d in n + w).items())),
              "categories: " + ", ".join(f"{k} {v}" for k, v in sorted(Counter(d.get("category") for d in n + w).items())),
              "culprit slots (nightly): " + ", ".join(f"{k} {v}" for k, v in sorted(Counter((d.get("solution") or {}).get("culprit") for d in n).items())),
              "difficulty (nightly): " + ", ".join(f"{k} {v}" for k, v in sorted(Counter(d.get("difficulty") for d in n).items()))]
    return "\n".join(lines) + "\n"


def _name_parts(name: str) -> tuple[str, str]:
    parts = name.replace("‌", "‌").split()
    return (parts[0], " ".join(parts[1:])) if parts else ("", "")


def name_map() -> dict[str, dict[str, list[str]]]:
    first: dict[str, list[str]] = {}
    last: dict[str, list[str]] = {}
    for d in nightly() + weekend() + story():
        for s in d.get("suspects", []):
            f, l = _name_parts(s["name"])
            first.setdefault(f, []).append(d["id"])
            if l:
                last.setdefault(l, []).append(d["id"])
    return {"first": first, "last": last}


def build_names() -> str:
    m = name_map()
    lines = ["# Names already used by suspects (GENERATED, do not edit by hand)", "",
             "A new case uses a first name AND a surname that appear nowhere here (also avoid near-homophones inside the case).",
             "Check one name: `python3 server/tools/case_index.py --find <name>`.", "", "## Surnames", ""]
    lines += [f"{k}: {', '.join(v)}" for k, v in sorted(m["last"].items())]
    lines += ["", "## First names", ""]
    lines += [f"{k}: {', '.join(v)}" for k, v in sorted(m["first"].items())]
    return "\n".join(lines) + "\n"


def next_slots() -> dict:
    n, w = nightly(), weekend()
    ln = n[-1]
    lw = max(w, key=lambda d: d["publish"])  # a weekend case may be written out of order (w012 was dated after w013)
    nn = int(ln["id"][1:]) + 1
    nw = max(int(d["id"][1:]) for d in w) + 1
    return {
        "nightly": [{"id": f"c{nn + i:03d}", "number": nn + i,
                     "publish": (date.fromisoformat(ln["publish"]) + timedelta(days=1 + i)).isoformat()} for i in range(2)],
        "weekend": {"id": f"w{nw:03d}", "number": nw, "publish": (date.fromisoformat(lw["publish"]) + timedelta(days=7)).isoformat()},
        "note": "nightly publish dates are contiguous (one per day); a weekend case publishes on a Thursday, 7 days after the last one",
    }


def main(argv: list[str]) -> int:
    if "--find" in argv:
        q = " ".join(argv[argv.index("--find") + 1:]).strip()
        m = name_map()
        hits = {kind: {k: v for k, v in m[kind].items() if q and (q == k or q in k)} for kind in m}
        print(json.dumps(hits, ensure_ascii=False, indent=1) if any(hits.values()) else f"'{q}' is free")
        return 0
    if "--next" in argv:
        print(json.dumps(next_slots(), ensure_ascii=False, indent=1))
        return 0
    idx, nam = build_index(), build_names()
    if "--check" in argv:
        old = (INDEX.read_text(encoding="utf-8") if INDEX.exists() else "", NAMES.read_text(encoding="utf-8") if NAMES.exists() else "")
        if old != (idx, nam):
            print("docs/case-index.md or docs/case-names.md is out of date: run python3 server/tools/case_index.py")
            return 1
        print("case index is up to date")
        return 0
    INDEX.write_text(idx, encoding="utf-8")
    NAMES.write_text(nam, encoding="utf-8")
    print(f"wrote {INDEX.relative_to(ROOT)} ({len(idx)} chars) and {NAMES.relative_to(ROOT)} ({len(nam)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
