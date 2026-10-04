"""Builds app/content/cases/cNNN.json from tools/cases_src/*.py  (run from server/:  python tools/build_cases.py)."""
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
OUT = HERE.parent / "app" / "content" / "cases"

built = []
for src in sorted((HERE / "cases_src").glob("*.py")):
    spec = importlib.util.spec_from_file_location(src.stem, src)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    built += mod.CASES
for c in built:
    (OUT / f"{c['id']}.json").write_text(json.dumps(c, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"built {len(built)} cases: {built[0]['id']} .. {built[-1]['id']}")
