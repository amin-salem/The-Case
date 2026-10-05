#!/usr/bin/env python3
"""Renders the launcher icon SVGs (tools/launcher/src) into the Android res/ PNGs (tools/launcher/res),
the Cafe Bazaar store icon and the in-app logo. Needs a Chrome/Chromium binary (CHROME=/path/to/chrome).

    python3 tools/launcher/render.py

tools/patch_android.py copies tools/launcher/res into android/app/src/main/res at build time.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC, RES = HERE / "src", HERE / "res"
APP = HERE.parent.parent
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
BACKGROUND = "#EFE6D6"  # the cream paper behind the fingerprint


def chrome() -> str:
    for c in [os.environ.get("CHROME", ""), "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
              shutil.which("chromium") or "", shutil.which("google-chrome") or "", shutil.which("chromium-browser") or ""]:
        if c and Path(c).exists():
            return c
    raise SystemExit("No Chrome/Chromium found: set CHROME=/path/to/chrome")


def render(svg: Path, size: int, out: Path) -> None:
    """Draws the SVG at 1024 px with Chrome (transparent background), then scales it down with Pillow."""
    from PIL import Image

    out.parent.mkdir(parents=True, exist_ok=True)
    big = 1024
    with tempfile.TemporaryDirectory() as tmp:
        page, shot = Path(tmp) / "p.html", Path(tmp) / "shot.png"
        page.write_text(f'<html><body style="margin:0;background:transparent">'
                        f'<img src="{svg.as_uri()}" width="{big}" height="{big}" style="display:block"></body></html>')
        subprocess.run([chrome(), "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", f"--window-size={big + 100},{big + 300}",
                        f"--screenshot={shot}", page.as_uri()], check=True, capture_output=True, timeout=60)
        img = Image.open(shot).convert("RGBA").crop((0, 0, big, big))
    img.resize((size, size), Image.LANCZOS).save(out, optimize=True)


def main() -> None:
    if RES.exists():
        shutil.rmtree(RES)
    for name, f in DENSITIES.items():
        render(SRC / "icon_legacy.svg", round(48 * f), RES / f"mipmap-{name}" / "ic_launcher.png")
        render(SRC / "icon_foreground.svg", round(108 * f), RES / f"mipmap-{name}" / "ic_launcher_foreground.png")
        render(SRC / "icon_monochrome.svg", round(108 * f), RES / f"mipmap-{name}" / "ic_launcher_monochrome.png")
        render(SRC / "icon_notification.svg", round(24 * f), RES / f"drawable-{name}" / "ic_stat_case.png")
    (RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (RES / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n')
    (RES / "values").mkdir(parents=True, exist_ok=True)
    (RES / "values" / "ic_launcher_colors.xml").write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n')
    render(SRC / "icon_full.svg", 512, HERE / "store" / "icon_512.png")  # Cafe Bazaar listing
    render(SRC / "icon_legacy.svg", 512, APP / "assets" / "icon" / "logo.png")  # in-app logo
    print("rendered into", RES)


if __name__ == "__main__":
    main()
