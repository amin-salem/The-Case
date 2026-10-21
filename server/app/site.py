"""The public landing page at «/» with a playable demo case (21 Oct 2026).

One self-contained HTML file (app/web/index.html): no database, no template engine, no external host (the font is our own
/static/fonts), read once at import and handed out with a cache header and an ETag, so it can never slow the API.
The demo case «نسخه‌ی گمشده» lives only inside that file: it is NOT a game case (archive cases are sold for coins),
it is not in app/content and no validator or the app ever loads it."""
import hashlib
from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, Response

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
                                       "font-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"}


@router.get("/", response_class=HTMLResponse)
async def landing(request: Request):
    if request.headers.get("if-none-match") == _ETAG:
        return Response(status_code=304, headers={"ETag": _ETAG, "Cache-Control": _HEADERS["Cache-Control"]})
    return HTMLResponse(_HTML, headers=_HEADERS)
