"""Public pages the stores ask for: privacy policy, terms of use, and how to delete an account."""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["pages"], include_in_schema=False)

_STYLE = """
<style>
body{margin:0;background:#10141c;color:#ede6d8;font-family:Vazirmatn,Tahoma,sans-serif;line-height:1.9}
main{max-width:760px;margin:0 auto;padding:32px 20px 64px}
h1{color:#d4a84b;font-size:26px}h2{color:#d4a84b;font-size:19px;margin-top:28px}
a{color:#e8a87c}p,li{font-size:16px}.muted{color:#8e97a8;font-size:14px}
</style>
"""

_CONTACT = "aminsaalem@gmail.com"


def _page(title: str, body: str) -> HTMLResponse:
    html = (f'<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title>{_STYLE}</head>'
            f'<body><main><h1>{title}</h1>{body}<p class="muted">آخرین به‌روزرسانی: مهر ۱۴۰۵</p></main></body></html>')
    return HTMLResponse(html)


@router.get("/privacy", response_class=HTMLResponse)
async def privacy():
    return _page("حریم خصوصی «پرونده»", f"""
<p>«پرونده» یک بازی معمایی است. ما فقط اطلاعاتی را نگه می‌داریم که برای اجرای بازی لازم است، و آن را به هیچ‌کس نمی‌فروشیم.</p>
<h2>چه اطلاعاتی نگه می‌داریم</h2>
<ul>
<li>یک شناسه‌ی تصادفی برای حساب و گوشی شما (بدون نیاز به ثبت‌نام).</li>
<li>نام مستعاری که خودتان انتخاب می‌کنید، و پیشرفت بازی: پرونده‌های حل‌شده، ستاره‌ها، سکه‌ها و زنجیره‌ی روزها.</li>
<li>اگر خودتان حساب را با ایمیل امن کنید: ایمیل و رمز عبور (رمز به‌صورت درهم‌شده و غیرقابل‌بازگشت ذخیره می‌شود).</li>
<li>برای خریدهای درون‌برنامه‌ای: شناسه‌ی خرید که فروشگاه (مایکت یا کافه‌بازار) می‌دهد، تا خرید را تأیید کنیم. اطلاعات کارت بانکی شما هرگز به ما نمی‌رسد.</li>
<li>آمار ساده‌ی استفاده (مثلاً باز شدن یک پرونده) برای بهتر کردن بازی، بدون اطلاعات شخصی.</li>
</ul>
<h2>چه اطلاعاتی نگه نمی‌داریم</h2>
<p>به مخاطبین، عکس‌ها، موقعیت مکانی، میکروفون یا دوربین شما دسترسی نداریم.</p>
<h2>نمایش در جدول امتیازات</h2>
<p>نام مستعار، چهره‌ی کارآگاه و امتیاز شما در جدول امتیازات به بقیه‌ی بازیکنان نشان داده می‌شود.</p>
<h2>اعلان‌ها</h2>
<p>یادآوری ساعت ۹ شب روی خود گوشی زمان‌بندی می‌شود و هر وقت بخواهید از تنظیمات بازی خاموش می‌شود.</p>
<h2>حذف حساب</h2>
<p>از «پرونده‌ی شخصی» در بازی، گزینه‌ی «حذف حساب» را بزنید؛ حساب و پیشرفت شما برای همیشه پاک می‌شود. اگر به بازی دسترسی ندارید، به {_CONTACT} ایمیل بزنید.</p>
<h2>تماس</h2>
<p>پرسش یا درخواست: <a href="mailto:{_CONTACT}">{_CONTACT}</a></p>
""")


@router.get("/terms", response_class=HTMLResponse)
async def terms():
    return _page("قوانین استفاده از «پرونده»", f"""
<ul>
<li>داستان‌ها، شخصیت‌ها و مکان‌های بازی خیالی‌اند و هر شباهتی به افراد یا رویدادهای واقعی تصادفی است.</li>
<li>سکه‌ها و امتیازها ارزش پولی ندارند و قابل تبدیل به پول یا انتقال به حساب دیگر نیستند.</li>
<li>خریدهای درون‌برنامه‌ای از طریق فروشگاهی انجام می‌شود که بازی را از آن گرفته‌اید و تابع قوانین بازپرداخت همان فروشگاه است. اگر پرداخت انجام شد ولی سکه نرسید، با ما تماس بگیرید.</li>
<li>استفاده از ترفند، چند حساب یا هر روش غیرمنصفانه برای بالا رفتن در جدول امتیازات ممنوع است و ممکن است به مسدود شدن حساب منجر شود.</li>
<li>نام مستعار توهین‌آمیز یا تبلیغاتی مجاز نیست.</li>
</ul>
<p>تماس: <a href="mailto:{_CONTACT}">{_CONTACT}</a></p>
""")


@router.get("/delete-account", response_class=HTMLResponse)
async def delete_account_info():
    return _page("حذف حساب «پرونده»", f"""
<p>در بازی به «پرونده‌ی شخصی» بروید و «حذف حساب» را بزنید. حساب، پیشرفت، سکه‌ها و ایمیل شما بلافاصله و برای همیشه پاک می‌شود.</p>
<p>اگر به بازی دسترسی ندارید، از ایمیل حسابتان به <a href="mailto:{_CONTACT}">{_CONTACT}</a> بنویسید.</p>
""")
