"""The public landing page at «/» with a playable demo case (21 Oct 2026).

One self-contained HTML file (app/web/index.html): no database, no template engine, no external host (the font is our own
/static/fonts), read once at import and handed out with a cache header and an ETag, so it can never slow the API.
The demo case «نسخه‌ی گمشده» lives only inside that file: it is NOT a game case (archive cases are sold for coins),
it is not in app/content and no validator or the app ever loads it."""
import hashlib
import html
import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response
from sqlalchemy.ext.asyncio import AsyncSession

from . import content
from .db import get_session
from .models import utcnow
from .services import promo

router = APIRouter(tags=["site"], include_in_schema=False)

# TODO(Amin): the real address of the game page on Cafe Bazaar (the same as `update_url` in services/remote_config.py).
# This is the ONLY place the site gets the download link from.
BAZAAR_URL = "https://cafebazaar.ir/app/ir.gammly.parvandeh"

_FILE = Path(__file__).resolve().parent / "web" / "index.html"
_MAX_BYTES = 120_000   # the page stays small: a phone on a bad network must load it fast


def _build() -> tuple[str, str]:
    html = _FILE.read_text(encoding="utf-8").replace("{{BAZAAR_URL}}", BAZAAR_URL)
    assert len(html.encode("utf-8")) <= _MAX_BYTES, "landing page too big"
    return html, '"' + hashlib.sha1(html.encode("utf-8")).hexdigest()[:16] + '"'


_HTML, _ETAG = _build()
_HEADERS = {"Cache-Control": "public, max-age=300", "ETag": _ETAG, "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
                                       "font-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"}


@router.get("/", response_class=HTMLResponse)
async def landing(request: Request):
    if request.headers.get("if-none-match") == _ETAG:
        return Response(status_code=304, headers={"ETag": _ETAG, "Cache-Control": _HEADERS["Cache-Control"]})
    return HTMLResponse(_HTML, headers=_HEADERS)


_IMG_DIR = Path(__file__).resolve().parent / "web" / "img"
_IMAGES = {f.name for f in _IMG_DIR.glob("*.webp")}   # a fixed list read once: nothing else is ever served from here


@router.get("/site-img/{name}")
async def site_image(name: str):
    """The pictures of the landing page (scenes, faces, frames, logo): our own files, cached for a week."""
    if name not in _IMAGES:
        raise HTTPException(404, "no_image")
    return FileResponse(_IMG_DIR / name, media_type="image/webp", headers={"Cache-Control": "public, max-age=604800"})


# ---- the page of one case, for ad links (2 Nov 2026): «/c/c020» ----
_CASE_ID = re.compile(r"^[cw]\d{3}$")
_FA = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
_CASE_PAGE = """<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · پرونده</title>
<meta name="description" content="{intro_short}"><meta property="og:title" content="{title} · پرونده">
<meta property="og:description" content="{intro_short}"><meta property="og:type" content="website">
<link rel="icon" href="/site-img/logo.webp" type="image/webp"><meta name="theme-color" content="#17181a">
<style>@font-face{{font-family:"Vazirmatn";font-weight:400;src:url(/static/fonts/Vazirmatn-Regular.ttf) format("truetype")}}
@font-face{{font-family:"Vazirmatn";font-weight:900;src:url(/static/fonts/Vazirmatn-Black.ttf) format("truetype")}}
:root{{--night:#17181a;--night3:#2b2d31;--text:#e6e2da;--soft:#a3a199;--stamp:#d0543f;--brass:#e0a526}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--night);color:var(--text);font:17px/1.9 Vazirmatn,Tahoma,sans-serif}}
.tape{{height:14px;background:repeating-linear-gradient(135deg,var(--brass) 0 18px,#17181a 18px 36px)}}
main{{max-width:560px;margin:0 auto;padding:28px 20px 40px}}
.badge{{display:inline-block;background:var(--night3);border:1px solid #3a3c41;color:var(--brass);padding:2px 14px;border-radius:99px;font-size:14px;font-weight:900}}
h1{{font-size:32px;line-height:1.4;margin:14px 0 6px;font-weight:900}}.meta{{color:var(--soft);font-size:15px;margin:0 0 16px}}
.intro{{background:var(--night3);border-radius:14px;padding:16px 18px;margin:0 0 20px}}
.btn{{display:flex;align-items:center;justify-content:center;min-height:54px;border-radius:14px;background:var(--stamp);color:#fff;font:900 18px Vazirmatn,Tahoma,sans-serif;text-decoration:none;box-shadow:0 6px 0 #8f3322}}
.note{{color:var(--soft);font-size:14px;margin-top:16px}}a.home{{color:var(--brass)}}</style></head><body>
<div class="tape"></div><main>{badge}<h1>{title}</h1><p class="meta">{meta}</p>
<div class="intro">{intro}</div>
<a class="btn" href="{bazaar}" rel="noopener">دانلود از کافه‌بازار</a>
<p class="note">{note}</p><p class="note"><a class="home" href="/">پرونده؛ بازی معمایی هر شب</a></p></main></body></html>"""


@router.get("/c/{case_id}", response_class=HTMLResponse)
async def case_page(case_id: str, session: AsyncSession = Depends(get_session)):
    """A shareable page for one published case (title, opening text, download link). It shows nothing a player does not
    already see before opening the case; a weekend case that is still live, a story chapter or an unknown id go to «/»."""
    if not _CASE_ID.match(case_id) or content.is_story(case_id):
        return RedirectResponse("/", status_code=302)
    weekly = content.is_weekly(case_id)
    c = content.weekly_by_id(case_id) if weekly else content.by_id(case_id)
    now = content.now_local()
    if c is None or content.opens_at(c) > now or (weekly and now < content.weekly_closes_at(c)):
        return RedirectResponse("/", status_code=302)
    ends = (await promo.active(session)).get(case_id)
    today = content.todays_case(now)
    d = c.data
    title, intro = str(d.get("title", "")), str(d.get("intro", ""))
    short = (intro[:150] + "…") if len(intro) > 150 else intro
    n = len(d.get("suspects", []))
    meta = f"{n} مظنون · سختی {int(d.get('difficulty') or 3)} از ۵".translate(_FA)
    if ends is not None:
        hours = max(1, int((ends - utcnow()).total_seconds() // 3600))
        badge = f'<span class="badge">رایگان برای کارآگاه‌های تازه · حدود {hours} ساعت دیگر</span>'.translate(_FA)
        note = "برنامه را نصب کن؛ این پرونده در صفحه‌ی اصلی منتظرته و بدون سکه بازش می‌کنی. این فرصت برای حساب‌های تازه است."
    elif today is not None and today.id == case_id:
        badge, note = '<span class="badge">پرونده‌ی امشب</span>', "این پرونده امشب برای همه رایگان است."
    else:
        badge, note = '<span class="badge">پرونده‌ی بایگانی</span>', "این پرونده در بخش بایگانی برنامه است."
    page = _CASE_PAGE.format(title=html.escape(title), intro_short=html.escape(short, quote=True), badge=badge,
                             meta=html.escape(meta), intro=html.escape(intro).replace("\n", "<br>"), bazaar=BAZAAR_URL,
                             note=html.escape(note))
    return HTMLResponse(page, headers={"Cache-Control": "public, max-age=60", "X-Content-Type-Options": "nosniff",
                                      "Content-Security-Policy": _HEADERS["Content-Security-Policy"]})
