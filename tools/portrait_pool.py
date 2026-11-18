"""List portraits that fit a suspect, least used first (so writers spread faces; Amin, 18 Nov 2026).

Usage: python3 tools/portrait_pool.py <m|f> <age> "<role and intro text>" [--exclude id,id]
"""
import collections
import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from art_rules import available, incompatibilities  # noqa: E402


def main(argv):
    if len(argv) < 4:
        raise SystemExit(__doc__)
    gender, age, role = argv[1], int(argv[2]), argv[3]
    exclude = set(argv[argv.index("--exclude") + 1].split(",")) if "--exclude" in argv else set()
    reg = {p["id"]: p for p in json.loads((ROOT / "docs/art-registry.json").read_text(encoding="utf-8"))["portraits"]}
    rel = json.loads((ROOT / "docs/portrait-release.json").read_text(encoding="utf-8"))
    use = collections.Counter()
    last = {}
    for f in sorted(glob.glob(str(ROOT / "server/app/content/cases/*.json")) + glob.glob(str(ROOT / "server/app/content/weekly/*.json"))):
        d = json.loads(Path(f).read_text(encoding="utf-8"))
        for s in d.get("suspects", []):
            p = s["avatar"].get("portrait")
            use[p] += 1
            last[p] = d["id"]
    suspect = {"role": role, "intro": "", "age": age, "avatar": {"gender": gender}}
    rows = []
    for pid, p in reg.items():
        if pid in exclude or not p.get("new_assignments_ok") or incompatibilities(p, suspect) or not available(pid, {"publish": "9999"}, rel):
            continue
        rows.append((use[pid], pid, p["apparent_age"], last.get(pid, "-")))
    for n, pid, a, lc in sorted(rows):
        print(f"{n}x  {pid:28} age {a:3}  last case {lc}")
    print(f"{len(rows)} compatible faces; take the first lines (least used).")


if __name__ == "__main__":
    main(sys.argv)
