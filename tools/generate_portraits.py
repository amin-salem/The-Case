#!/usr/bin/env python3
"""Generate every image listed in docs/portrait-prompts-v3-chatgpt.md with the OpenAI Images API.

Run on YOUR computer (not in chat). The key stays in an environment variable.
  pip install openai
  export OPENAI_API_KEY=sk-...        (Windows PowerShell: $env:OPENAI_API_KEY="sk-...")
  python tools/generate_portraits.py --out portraits_out --quality medium
Safe to stop and run again: files that already exist are skipped.
  --dry-run            only list what would be made (no key, no cost)
  --only m_mid_tailor  make one item (or several, comma separated)
  --limit 5            make only the first 5 missing items (test run)
"""
import argparse, base64, os, re, sys, time
from pathlib import Path

DEFAULT_MD = Path(__file__).resolve().parent.parent / "docs" / "portrait-prompts-v3-chatgpt.md"

def parse(md: str):
    return re.findall(r"### \d+\. `([^`]+)\.png`\n```\n(.*?)\n```", md, re.S)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", default=str(DEFAULT_MD))
    ap.add_argument("--out", default="portraits_out")
    ap.add_argument("--quality", default="medium", choices=["low", "medium", "high"])
    ap.add_argument("--model", default="gpt-image-1")
    ap.add_argument("--only", default="")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--pause", type=float, default=2.0, help="seconds between requests")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    items = parse(Path(a.md).read_text(encoding="utf-8"))
    if a.only:
        want = set(a.only.split(","))
        items = [x for x in items if x[0] in want]
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    todo = [(i, p) for i, p in items if not (out / f"{i}.png").exists()]
    if a.limit:
        todo = todo[: a.limit]
    print(f"{len(items)} items in file, {len(todo)} to make, quality={a.quality}")
    if a.dry_run:
        for i, _ in todo: print("  would make", i)
        return
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("Set OPENAI_API_KEY first (see the top of this file).")
    from openai import OpenAI
    client = OpenAI()
    done = failed = 0
    for n, (i, prompt) in enumerate(todo, 1):
        for attempt in range(1, 5):
            try:
                r = client.images.generate(model=a.model, prompt=prompt, size="1024x1024", quality=a.quality, n=1)
                (out / f"{i}.png").write_bytes(base64.b64decode(r.data[0].b64_json))
                done += 1
                print(f"[{n}/{len(todo)}] {i}.png ok")
                break
            except Exception as e:  # rate limit, moderation, network
                wait = 10 * attempt
                print(f"[{n}/{len(todo)}] {i}: {type(e).__name__}: {str(e)[:120]} (try {attempt}, wait {wait}s)")
                time.sleep(wait)
        else:
            failed += 1
            print(f"  GAVE UP on {i}; run the script again later")
        time.sleep(a.pause)
    print(f"finished: {done} made, {failed} failed. Folder: {out.resolve()}")

if __name__ == "__main__":
    main()
