"""Public pages (privacy, terms, delete-account, support) and the landing page with the demo case at «/»."""
import re

from app import site
from app.routers import pages

PAGES = {
    "/privacy": ["اطلاعاتی که جمع می‌کنیم", "چرا این اطلاعات را استفاده می‌کنیم", "چه چیزی را چه کسی می‌بیند",
                 "نظرها و امتیازها", "تقلب و مسدود شدن", "نگهداری و حذف اطلاعات", "کودکان", "تماس"],
    "/terms": ["سکه‌ها و خرید", "بازپرداخت", "رفتار منصفانه و مسدود شدن", "مالکیت محتوا", "حذف حساب", "تغییر قوانین", "تماس"],
    "/delete-account": ["مراحل", "چه چیزی حذف می‌شود", "چه چیزی می‌ماند", "اگر به بازی دسترسی ندارید"],
    "/support": ["تماس با ما", "پرسش‌های رایج", "قوانین و حریم خصوصی"],
}


async def test_every_public_page_is_200_with_its_headings(client):
    for path, headings in PAGES.items():
        r = await client.get(path)
        assert r.status_code == 200, path
        assert r.headers["content-type"].startswith("text/html")
        assert "max-age" in r.headers.get("cache-control", "")
        assert len(r.content) < 40_000
        assert pages.UPDATED in r.text and pages.CONTACT in r.text
        for h in headings:
            assert f"<h2>{h}</h2>" in r.text, (path, h)
        assert "http://" not in r.text and "https://" not in r.text  # no external host at all


async def test_landing_page_has_the_demo_and_no_external_host(client):
    r = await client.get("/")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert "max-age" in r.headers["cache-control"] and r.headers["etag"]
    html = r.text
    assert "یه پرونده‌ی آزمایشی رو خودت حل کن" in html and "دانلود از کافه بازار" in html
    assert "نسخه‌ی گمشده" in html and html.count('id:"e') == 6 and html.count('id:"s') == 4
    assert "{{" not in html
    # every address in the page is the Bazaar button (or part of nothing else); no script/style/img/font from elsewhere
    urls = set(re.findall(r"https?://[^\s\"'<>)]+", html))
    assert urls <= {site.BAZAAR_URL}, urls
    assert not re.search(r"<(script|link|img|iframe)[^>]+(src|href)=[\"']https?:", html)
    assert "@import" not in html and "//cdn" not in html
    # conditional request: unchanged page costs nothing
    r2 = await client.get("/", headers={"If-None-Match": r.headers["etag"]})
    assert r2.status_code == 304
    assert (await client.get("/health")).status_code == 200


def test_demo_case_is_not_part_of_the_game():
    from app import content
    ids = {c.id for c in content.all_cases()} | {c.id for c in content.weekly_cases()}
    assert not any("نسخه‌ی گمشده" in str(c.data.get("title")) for c in content.all_cases())
    assert "demo" not in ids
