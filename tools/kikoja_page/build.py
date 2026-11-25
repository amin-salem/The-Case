"""Builds app/assets/kikoja/index.html (one self-contained page) from src.html + fonts.css + plan.py + portraits.
Run from the repo root:  python3 tools/kikoja_page/build.py"""
import base64, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PORTRAITS = {  # page name -> portrait file (all released, neutral clothes; women with a scarf)
    "mina": "f_neutral_27_coils", "nasrin": "f_neutral_20_pixie", "taraneh": "f_neutral_29_square",
    "kaveh": "m_neutral_29_coils", "bahram": "m_neutral_24_freckles", "mansour": "m_neutral_62_soft",
    "farhad": "m_neutral_41_oval", "reza": "m_neutral_45_waves",
}

def data_uri(name: str) -> str:
    raw = (ROOT / "app/assets/portraits" / f"{name}.webp").read_bytes()
    return "data:image/webp;base64," + base64.b64encode(raw).decode()

def plan(house: str) -> str:
    return subprocess.run([sys.executable, str(HERE / "plan.py"), house], check=True, capture_output=True, text=True).stdout.strip()

def js(s: str) -> str:
    import json
    return json.dumps(s, ensure_ascii=False)

def main() -> None:
    src = (HERE / "src.html").read_text(encoding="utf-8")
    imgs = "{" + ",".join(f"{k}:{js(data_uri(v))}" for k, v in PORTRAITS.items()) + "}"
    plans = "{" + ",".join(f"{h}:{js(plan(h))}" for h in ("qolhak", "kashan")) + "}"
    out = (src.replace("/*__FONTS__*/", (HERE / "fonts.css").read_text()).replace("/*__IMG__*/", imgs).replace("/*__PLANS__*/", plans))
    dest = ROOT / "app/assets/kikoja/index.html"
    dest.write_text(out, encoding="utf-8")
    print(dest, len(out) // 1024, "KB")

main()
