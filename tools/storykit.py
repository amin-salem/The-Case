"""Shared library of the story/case kit (docs/story-workflow.md).

Everything here is deterministic, offline and stdlib-only: no network, no paid API. The server's own validators
(`server/app/content.py`) are reused as the last gate, so a chapter that passes this kit also loads on the server.

Used by tools/validate_story.py, validate_case.py, import_story.py, import_case.py.
"""
from __future__ import annotations

import bisect
import importlib.util
import json
import re
import sys
import types
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------------------------------------------
# Limits. (soft_lo, soft_hi, hard_lo, hard_hi): outside soft = warning, outside hard = error.
# The ChatGPT prompt (docs/story-chatgpt-prompt.md) lists the SOFT ranges in a `limits` block; a test keeps them equal.
# unit: "w" words, "c" characters, "n" count.
LIMITS: dict[str, tuple[str, int, int, int, int]] = {
    "scene.text": ("w", 60, 140, 45, 175),
    "scenes": ("n", 4, 5, 2, 8),
    "scene.options": ("n", 2, 3, 1, 3),
    "option.title": ("c", 6, 60, 3, 120),
    "option.sub": ("c", 0, 70, 0, 240),
    "ending.text": ("c", 60, 500, 20, 1400),
    "board.clue.title": ("c", 5, 50, 2, 120),
    "board.clue.text": ("c", 30, 300, 0, 600),
    "title": ("c", 3, 40, 2, 80),
    "location": ("c", 10, 120, 5, 200),
    "intro": ("c", 150, 1000, 80, 1600),
    "suspects": ("n", 5, 6, 3, 6),
    "suspect.name": ("c", 3, 30, 2, 40),
    "suspect.role": ("c", 5, 70, 2, 120),
    "suspect.intro": ("c", 20, 90, 20, 90),
    "suspect.motive": ("c", 20, 220, 10, 400),
    "suspect.statement": ("c", 120, 650, 60, 1100),
    "suspect.questions": ("n", 3, 6, 2, 8),
    "question.q": ("c", 5, 80, 3, 140),
    "question.a": ("c", 40, 520, 15, 900),
    "evidence": ("n", 7, 9, 5, 16),
    "evidence.title": ("c", 8, 90, 3, 140),
    "evidence.text": ("c", 120, 800, 40, 1400),
    "hint": ("c", 40, 380, 15, 600),
    "explanation": ("c", 400, 2600, 150, 4200),
    "partner_intro": ("c", 250, 1100, 100, 1500),
    "partner_outro": ("c", 120, 900, 50, 1400),
    "thread": ("c", 60, 420, 25, 700),
    "kit.summary": ("c", 120, 700, 60, 1200),
    "notify.head": ("c", 6, 35, 3, 45),
    "notify.body": ("c", 20, 90, 10, 140),
}

SCENE_ID_RE = re.compile(r"^[A-Za-z0-9_]{1,24}$")
HAIR = {"bald", "hijab", "slick", "short", "cap", "curly"}
BEARD = {"none", "mustache", "full", "stubble"}
ACCESSORY = {"none", "tie", "scarf", "badge", "apron"}
AGES = {"young", "mid", "old"}
EVID_TYPES = {"document", "object", "witness", "cctv", "receipt", "forensic", "phone"}

TOP_CASE = {"id", "number", "publish", "difficulty", "scene", "title", "location", "intro", "suspects", "evidence",
            "hints", "solution"}
TOP_STORY = TOP_CASE | {"season", "chapter", "partner_hints", "partner_intro", "partner_outro_win",
                        "partner_outro_lose", "thread", "scenes", "ending", "board"}
META_KEYS = {"_kit", "_notify"}  # kit-only keys: validated here, removed by the importers, never shipped

# ---------------------------------------------------------------------------------------------------------------
# Word lists (Persian text only). Keep them short and obvious: a long list makes false alarms.
BRANDS = ["سامسونگ", "اپل", "آیفون", "گوگل", "تلگرام", "واتساپ", "واتس‌اپ", "اینستاگرام", "ایتا", "روبیکا", "ایرانسل",
          "همراه اول", "رایتل", "دیجی‌کالا", "دیجی کالا", "دیوار", "شیپور", "اسنپ", "تپسی", "ایران‌خودرو", "سایپا", "پژو",
          "پراید", "سمند", "تویوتا", "بنز", "بی‌ام‌و", "نایک", "آدیداس", "کوکاکولا", "پپسی", "نوکیا", "شیائومی", "هواوی",
          "آمازون", "نتفلیکس", "یوتیوب", "فیس‌بوک", "توییتر", "بانک ملی", "بانک ملت", "بانک صادرات", "بانک سپه",
          "بانک پاسارگاد", "بانک سامان", "بانک پارسیان", "بانک تجارت", "بانک رفاه", "بانک کشاورزی", "بانک مسکن"]
REAL_PEOPLE_POLITICS = ["خامنه‌ای", "خمینی", "رضاشاه", "محمدرضا شاه", "مصدق", "ترامپ", "بایدن", "پوتین", "سپاه", "بسیج",
                        "آیت‌الله", "رئیس‌جمهور", "مجلس شورا"]
RELIGIOUS_PLACES = ["حرم", "امامزاده", "امام‌زاده", "گوهرشاد", "جمکران"]
REAL_CITIES = ["تهران", "اصفهان", "شیراز", "تبریز", "مشهد", "کرج", "اهواز", "قم", "کرمان", "رشت", "یزد", "ارومیه"]
GORE = ["مثله", "تکه‌تکه", "شکنجه", "تجاوز", "سربریده", "سر بریده", "روده", "تیرباران", "اعدام", "خودکشی", "خودکشی"]
PLAYER_WORDS = ["بازیکن", "کاربر", "پلیر", "گیمر"]
GUILT = (r"(?:قاتل|مجرم|گناهکار|مقصر|خلافکار|دزد اصلی|عامل اصلی|خودش بود|کار او(?:ست| بود)|کار خودشه|اعتراف کرد)")
INTRO_FORBIDDEN = ["انگیزه", "دروغ", "بدهی", "قرض", "راز", "مشکوک", "مظنون", "قاتل", "مجرم", "گناه", "شک", "پنهان",
                   "دعوا", "اختلاف", "کینه", "ورشکست", "طلبکار"]
OUTCOME_WORDS = ["درست حدس زدی", "متهم اصلی", "کار او بود", "کار اون بود", "پرونده بسته شد", "گیر افتاد"]

FA_DIGITS = str.maketrans("0123456789٠١٢٣٤٥٦٧٨٩", "۰۱۲۳۴۵۶۷۸۹۰۱۲۳۴۵۶۷۸۹")
AR_LETTERS = str.maketrans({"ي": "ی", "ك": "ک", "ى": "ی"})
BIDI = re.compile("[\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]")
MI_SPACE = re.compile(r"(?<![\u0622-\u06CC\u200c])(ن?می) (?=[\u0622-\u06CC])")
HA_SPACE = re.compile(r"(?<=[\u0622-\u06CC]) (ها|های|هایی)(?![\u0622-\u06CC\u200c])")
LATIN = re.compile(r"[A-Za-z]")
PERSIAN_RANGE = "\u0622-\u06CC\u200c"  # letters only: the Arabic comma/semicolon/question mark must count as punctuation

# keys whose string values are ids/enums, never prose
SKIP_KEYS = {"id", "goes_to", "gives_clue", "needs_clue", "speaker", "type", "culprit", "proof", "publish"}
SKIP_PARENTS = {"avatar", "relations"}


def fa(n) -> str:
    return str(n).translate(FA_DIGITS)


# ---------------------------------------------------------------------------------------------------------------
@dataclass
class Issue:
    sev: str                  # "error" | "warn"
    code: str
    msg: str                  # Persian: what is wrong
    fix: str                  # Persian: what to do
    path: tuple = ()
    line: int = 0
    auto: bool = False        # the importer repairs it by itself


@dataclass
class Report:
    issues: list[Issue] = field(default_factory=list)
    stats: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)

    def add(self, sev, code, msg, fix, path=(), auto=False):
        self.issues.append(Issue(sev, code, msg, fix, tuple(path), 0, auto))

    @property
    def errors(self):
        return [i for i in self.issues if i.sev == "error"]

    @property
    def warnings(self):
        return [i for i in self.issues if i.sev == "warn"]

    @property
    def ok(self):
        return not self.errors


# ---------------------------------------------------------------------------------------------------------------
# JSON with line numbers
class JsonLineError(ValueError):
    def __init__(self, msg, line):
        super().__init__(msg)
        self.line = line


def parse_json_lines(text: str):
    """(object, {path_tuple: line}) - a tiny JSON parser that remembers on which line every value starts."""
    starts = [0] + [m.end() for m in re.finditer("\n", text)]

    def line_of(pos):
        return bisect.bisect_right(starts, pos)

    ws = re.compile(r"\s*")
    num = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?")
    lines: dict[tuple, int] = {}

    def skip(i):
        return ws.match(text, i).end()

    def fail(i, why):
        raise JsonLineError(why, line_of(min(i, len(text) - 1 if text else 0)))

    def parse(i, path):
        i = skip(i)
        if i >= len(text):
            fail(i, "JSON ناقص است (فایل زودتر از موقع تمام شد؛ احتمالاً پاسخ ChatGPT نصفه ماند)")
        lines[path] = line_of(i)
        c = text[i]
        if c == "{":
            out, i = {}, skip(i + 1)
            if text[i:i + 1] == "}":
                return out, i + 1
            while True:
                i = skip(i)
                if text[i:i + 1] != '"':
                    fail(i, "کلید باید در گیومه‌ی دوتایی باشد (ویرگول اضافه یا گیومه‌ی جاافتاده؟)")
                try:
                    key, i2 = json.decoder.scanstring(text, i + 1)
                except json.JSONDecodeError as e:
                    fail(i, f"رشته درست بسته نشده ({e.msg})")
                lines[path + (key,)] = line_of(i)
                i = skip(i2)
                if text[i:i + 1] != ":":
                    fail(i, "بعد از کلید «:» لازم است")
                val, i = parse(i + 1, path + (key,))
                out[key] = val
                i = skip(i)
                if text[i:i + 1] == ",":
                    i += 1
                    continue
                if text[i:i + 1] == "}":
                    return out, i + 1
                fail(i, "بعد از مقدار «,» یا «}» لازم است (ویرگول جاافتاده؟)")
        if c == "[":
            out, i = [], skip(i + 1)
            if text[i:i + 1] == "]":
                return out, i + 1
            while True:
                val, i = parse(i, path + (len(out),))
                out.append(val)
                i = skip(i)
                if text[i:i + 1] == ",":
                    i += 1
                    continue
                if text[i:i + 1] == "]":
                    return out, i + 1
                fail(i, "بعد از عضو آرایه «,» یا «]» لازم است (ویرگول جاافتاده؟)")
        if c == '"':
            try:
                s, i2 = json.decoder.scanstring(text, i + 1)
            except json.JSONDecodeError as e:
                fail(i, f"رشته درست بسته نشده ({e.msg}؛ گیومه‌ی دوتایی داخل متن باید \\\" یا «» باشد)")
            return s, i2
        for lit, val in (("true", True), ("false", False), ("null", None)):
            if text.startswith(lit, i):
                return val, i + len(lit)
        m = num.match(text, i)
        if m:
            s = m.group()
            return (float(s) if any(ch in s for ch in ".eE") else int(s)), m.end()
        fail(i, f"نویسه‌ی غیرمنتظره «{text[i]}»")

    obj, end = parse(0, ())
    if skip(end) != len(text):
        fail(skip(end), "بعد از پایان JSON متن اضافه هست")
    return obj, lines


def extract_json(raw: str):
    """ChatGPT often wraps JSON in ``` fences or adds a sentence. Returns (clean_text, [notes])."""
    notes = []
    t = raw.lstrip("\ufeff").strip()
    m = re.search(r"```(?:json|JSON)?\s*\n(.*?)\n```", t, re.S)
    if m:
        notes.append("خروجی داخل ``` بود؛ برای اعتبارسنجی بیرون کشیده شد (پرامپت می‌گوید فقط JSON خام)")
        t = m.group(1).strip()
    elif not t.startswith("{"):
        i, j = t.find("{"), t.rfind("}")
        if i != -1 and j > i:
            notes.append("قبل یا بعد از JSON متن اضافه بود؛ حذف شد")
            t = t[i:j + 1]
    return t, notes


def render_path(obj, path: tuple) -> str:
    """scenes[1](alley).options[0](ask).title - readable for Amin and for ChatGPT."""
    out, cur = "", obj
    for p in path:
        if isinstance(p, int):
            out += f"[{p}]"
            cur = cur[p] if isinstance(cur, list) and p < len(cur) else None
            if isinstance(cur, dict) and isinstance(cur.get("id"), str):
                out += f"({cur['id']})"
        else:
            out += ("." if out else "") + str(p)
            cur = cur.get(p) if isinstance(cur, dict) else None
    return out


# ---------------------------------------------------------------------------------------------------------------
# text helpers
def kind_of(path: tuple) -> str:
    """'id' (not prose) | 'meta' | 'post' (may name the culprit: solved already) | 'ui' | 'story'."""
    if not path:
        return "id"
    last = path[-1]
    if path[0] in META_KEYS:
        return "meta"
    if path[0] in {"id", "publish", "scene", "season", "chapter", "number", "difficulty"}:
        return "id"
    if any(p in SKIP_PARENTS for p in path) or "proof" in path or (isinstance(last, str) and last in SKIP_KEYS) or "gives_clue" in path or "needs_clue" in path:
        return "id"
    if path[0] in {"partner_outro_win", "partner_outro_lose", "thread"} or path[:2] == ("solution", "explanation"):
        return "post"
    if "scenes" in path and last in ("title", "sub"):
        return "ui"
    if "board" in path and last in ("title", "role", "name"):
        return "ui"
    return "story"


def walk_strings(obj, path=()):
    if isinstance(obj, str):
        yield path, obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk_strings(v, path + (k,))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_strings(v, path + (i,))


def normalize_text(s: str) -> str:
    """Characters only (never words): Arabic ي/ك, digits to Persian, bidi controls, spaces, نیم‌فاصله after «می»."""
    # evidence ids such as «e3» in the explanation keep their ASCII digit
    s = "".join(part if i % 2 else part.translate(AR_LETTERS).translate(FA_DIGITS)
                for i, part in enumerate(re.split(r"(\be\d+\b)", s)))
    s = BIDI.sub("", s)
    s = re.sub(r"[ \t]{2,}", " ", s).strip()
    s = MI_SPACE.sub("\\1\u200c", s)
    s = HA_SPACE.sub("\u200c\\1", s)
    return s


def autofix(obj):
    """Deep copy with every prose string normalised. Returns (new_obj, number_of_changed_strings)."""
    changed = 0

    def go(o, path):
        nonlocal changed
        if isinstance(o, str):
            if kind_of(path) in ("id", "meta"):
                return o
            n = normalize_text(o)
            if n != o:
                changed += 1
            return n
        if isinstance(o, dict):
            return {k: go(v, path + (k,)) for k, v in o.items()}
        if isinstance(o, list):
            return [go(v, path + (i,)) for i, v in enumerate(o)]
        return o

    return go(obj, ()), changed


def words(s: str) -> int:
    return len(s.split())


def _bound(rep: Report, key: str, value, path, label: str, unit_override=None):
    """Check `value` (a count) against LIMITS[key]; add warn/error with a Persian message."""
    unit, lo, hi, hlo, hhi = LIMITS[key]
    u = {"w": "کلمه", "c": "نویسه", "n": "مورد"}[unit_override or unit]
    if value < hlo or value > hhi:
        rep.add("error", "len", f"{label}: {fa(value)} {u} است؛ مجاز {fa(hlo)} تا {fa(hhi)}",
                f"{label} را به حدود {fa(lo)} تا {fa(hi)} {u} برسان", path)
    elif value < lo or value > hi:
        rep.add("warn", "len", f"{label}: {fa(value)} {u} است؛ هدف {fa(lo)} تا {fa(hi)}",
                f"{label} را به {fa(lo)} تا {fa(hi)} {u} نزدیک کن", path)


def _find_word(text: str, word: str) -> bool:
    return re.search(rf"(?<![{PERSIAN_RANGE}]){re.escape(word)}(?![{PERSIAN_RANGE}])", text) is not None


# ---------------------------------------------------------------------------------------------------------------
# content (server validators) - real import in CI/server, stub for `config` when the server's dependencies are missing
def load_content(root: Path = ROOT):
    if "app.content" in sys.modules:
        return sys.modules["app.content"]
    server = str(root / "server")
    try:
        if server not in sys.path:
            sys.path.insert(0, server)
        from app import content  # type: ignore
        return content
    except Exception:  # pydantic-settings & co. not installed on this machine: the validators only need get_settings()
        for name in [n for n in sys.modules if n == "app" or n.startswith("app.")]:
            del sys.modules[name]
        pkg = types.ModuleType("app")
        pkg.__path__ = [str(root / "server" / "app")]
        sys.modules["app"] = pkg
        cfg = types.ModuleType("app.config")
        cfg.get_settings = lambda: types.SimpleNamespace(timezone="Asia/Tehran", new_case_hour=21)
        sys.modules["app.config"] = cfg
        spec = importlib.util.spec_from_file_location("app.content", root / "server" / "app" / "content.py")
        mod = importlib.util.module_from_spec(spec)
        sys.modules["app.content"] = mod
        spec.loader.exec_module(mod)
        return mod


def story_dir(root: Path = ROOT) -> Path:
    return root / "server" / "app" / "content" / "story"


def cases_dir(root: Path = ROOT) -> Path:
    return root / "server" / "app" / "content" / "cases"


def portraits(root: Path = ROOT) -> set[str]:
    p = root / "app" / "assets" / "portraits"
    return {f.stem for f in p.glob("*.webp")} if p.is_dir() else set()


def load_kit(root: Path = ROOT, season: int = 1) -> dict:
    p = story_dir(root) / f"s{season:02d}" / "kit.json"
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"plan": {}, "chapters": {}}


# ---------------------------------------------------------------------------------------------------------------
# generic checks shared by cases and chapters
def check_text_rules(rep: Report, d: dict, story: bool):
    """Characters, wording, banned words. One warning per kind, listing up to five places."""
    kinds: dict[str, list[tuple]] = {}
    for path, s in walk_strings(d):
        k = kind_of(path)
        if k in ("id", "meta"):
            continue
        # characters
        if any(ch in s for ch in "يكى"):
            kinds.setdefault("arabic", []).append(path)
        if re.search("[0-9٠-٩]", re.sub(r"\be\d+\b", "", s)):
            kinds.setdefault("digits", []).append(path)
        if BIDI.search(s):
            kinds.setdefault("bidi", []).append(path)
        if re.search(r"[ \t]{2,}", s) or s != s.strip():
            kinds.setdefault("spaces", []).append(path)
        if MI_SPACE.search(s) or HA_SPACE.search(s):
            kinds.setdefault("zwnj", []).append(path)
        if LATIN.search(re.sub(r"\be\d+\b", "", s) if k == "post" else s):
            rep.add("error", "latin", f"حرف لاتین در متن: «{LATIN.search(s).group()}...»",
                    "همه‌ی متن‌ها فقط فارسی باشند؛ این بخش را فارسی بنویس", path)
        if '"' in s or "'" in s:
            rep.add("warn", "quotes", "گیومه‌ی انگلیسی داخل متن", "از «» استفاده کن", path)
        # wording
        for w in PLAYER_WORDS:
            if _find_word(s, w):
                rep.add("error", "player_word", f"کلمه‌ی «{w}» برای بازیکن ممنوع است",
                        "بازیکن را «کارآگاه» بنام (متن‌های برنامه همیشه «کارآگاه»)", path)
        if k == "ui" and _find_word(s, "نفر"):
            rep.add("error", "nafar", "در متن‌های رابط (عنوان گزینه، سرنخ، نقش) «نفر» ممنوع است",
                    "بازیکن‌ها «کارآگاه» و متهم‌ها «مظنون» شمرده می‌شوند", path)
        for w in BRANDS:
            if _find_word(s, w):
                rep.add("error", "brand", f"نام برند/سازمان واقعی: «{w}»", "برند خیالی یا عمومی بگذار (مثلاً «بانک»، «خودرو»)", path)
        for w in REAL_PEOPLE_POLITICS:
            if _find_word(s, w):
                rep.add("error", "politics", f"نام فرد یا نهاد واقعی/سیاسی: «{w}»", "حذف یا خیالی کن", path)
        for w in RELIGIOUS_PLACES:
            if _find_word(s, w):
                rep.add("warn", "religious", f"مکان مذهبی واقعی: «{w}»", "مکان خیالی یا عمومی بگذار", path)
        for w in GORE:
            if _find_word(s, w):
                rep.add("warn", "gore", f"واژه‌ی خشن: «{w}»", "نرم‌تر بنویس؛ بازی خشونت ندارد", path)
        if story:
            for w in REAL_CITIES:
                if _find_word(s, w):
                    rep.add("warn", "real_city", f"شهر واقعی «{w}»؛ شهر فصل‌ها «رازان» است", "نام خیالی/رازان بگذار", path)
    labels = {"arabic": ("حروف عربی «ي ك ى»", "به ی/ک فارسی تبدیل می‌شود"),
              "digits": ("رقم انگلیسی/عربی", "به ارقام فارسی (۰-۹) تبدیل می‌شود"),
              "bidi": ("نویسه‌ی کنترل جهت (RLM/LRM/BOM...)", "حذف می‌شود"),
              "spaces": ("فاصله‌ی دوتایی یا فاصله‌ی ابتدا/انتها", "اصلاح می‌شود"),
              "zwnj": ("«می ...»/«نمی ...»/«... ها» با فاصله به‌جای نیم‌فاصله", "با نیم‌فاصله جایگزین می‌شود")}
    for k, paths in kinds.items():
        what, how = labels[k]
        shown = "، ".join(render_path(d, p) for p in paths[:5])
        more = f" و {fa(len(paths) - 5)} مورد دیگر" if len(paths) > 5 else ""
        rep.add("warn", f"norm_{k}", f"{what} در {fa(len(paths))} متن ({shown}{more})",
                f"لازم نیست کاری کنی: هنگام وارد کردن خودکار {how}", paths[0], auto=True)


def check_suspects(rep: Report, d: dict, root: Path):
    sus = d.get("suspects")
    if not isinstance(sus, list):
        return
    _bound(rep, "suspects", len(sus), ("suspects",), "تعداد مظنون‌ها")
    ports = portraits(root)
    seen_ports: dict[str, str] = {}
    for i, s in enumerate(sus):
        if not isinstance(s, dict):
            continue
        base = ("suspects", i)
        name = s.get("name", "?")
        if s.get("id") != f"s{i + 1}":
            rep.add("warn", "sid", f"شناسه‌ی مظنون {name} باید s{i + 1} باشد (ترتیبی)", f"id را s{i + 1} کن", base + ("id",))
        for key, lim in (("name", "suspect.name"), ("role", "suspect.role"), ("motive", "suspect.motive"),
                         ("statement", "suspect.statement")):
            v = s.get(key)
            if isinstance(v, str):
                _bound(rep, lim, len(v.strip()), base + (key,), f"{name} / {key}")
            else:
                rep.add("error", "missing", f"{name}: فیلد {key} نیست", f"{key} را اضافه کن", base)
        intro = s.get("intro")
        if isinstance(intro, str):
            _bound(rep, "suspect.intro", len(intro.strip()), base + ("intro",), f"{name} / intro (معرفی خنثی)")
            intro_chk = intro.replace("رازان", "").replace("پزشک", "")  # «رازان» contains «راز», «پزشک» contains «شک»
            for w in INTRO_FORBIDDEN:
                if w in intro_chk:
                    rep.add("error", "intro_neutral", f"معرفیِ {name} خنثی نیست (کلمه‌ی «{w}»)",
                            "intro فقط بگوید او کیست (نقش و رابطه)؛ بدون انگیزه، دروغ، راز، بدهی یا شک", base + ("intro",))
                    break
            if re.search(GUILT, intro):
                rep.add("error", "leak", f"معرفیِ {name} واژه‌ی گناه دارد", "intro را خنثی کن", base + ("intro",))
        else:
            rep.add("error", "missing", f"{name}: intro (معرفی خنثی ۲۰ تا ۹۰ نویسه) نیست", "intro را اضافه کن", base)
        age = s.get("age")
        if not isinstance(age, int) or not 12 <= age <= 95:
            rep.add("error", "age", f"{name}: سن باید عدد ۱۲ تا ۹۵ باشد", "age را درست کن", base + ("age",))
        qs = s.get("questions")
        if isinstance(qs, list):
            _bound(rep, "suspect.questions", len(qs), base + ("questions",), f"{name}: تعداد پرسش‌ها")
            for j, q in enumerate(qs):
                if isinstance(q, dict) and isinstance(q.get("q"), str) and isinstance(q.get("a"), str):
                    _bound(rep, "question.q", len(q["q"].strip()), base + ("questions", j, "q"), f"{name} / پرسش {fa(j + 1)}")
                    _bound(rep, "question.a", len(q["a"].strip()), base + ("questions", j, "a"), f"{name} / پاسخ {fa(j + 1)}")
                else:
                    rep.add("error", "qa", f"{name}: پرسش {fa(j + 1)} باید {{q, a}} باشد", "q و a را بنویس", base + ("questions", j))
        av = s.get("avatar")
        if not isinstance(av, dict):
            rep.add("error", "avatar", f"{name}: avatar نیست", "avatar کامل بگذار", base)
            continue
        for key in ("gender", "age", "skin", "hair", "hairColor", "beard", "glasses", "outfit", "accessory", "portrait"):
            if key not in av:
                rep.add("error", "avatar", f"{name}: avatar.{key} نیست", "همه‌ی کلیدهای avatar را بگذار", base + ("avatar",))
        g = av.get("gender")
        if g not in ("m", "f"):
            rep.add("error", "avatar", f"{name}: gender باید m یا f باشد", "gender را درست کن", base + ("avatar", "gender"))
        if av.get("age") not in AGES:
            rep.add("error", "avatar", f"{name}: avatar.age باید یکی از {sorted(AGES)} باشد", "درست کن", base + ("avatar", "age"))
        if av.get("hair") not in HAIR:
            rep.add("error", "avatar", f"{name}: hair باید یکی از {sorted(HAIR)} باشد", "درست کن", base + ("avatar", "hair"))
        if av.get("beard") not in BEARD:
            rep.add("error", "avatar", f"{name}: beard باید یکی از {sorted(BEARD)} باشد", "درست کن", base + ("avatar", "beard"))
        if av.get("accessory") not in ACCESSORY:
            rep.add("error", "avatar", f"{name}: accessory باید یکی از {sorted(ACCESSORY)} باشد", "درست کن", base + ("avatar", "accessory"))
        if av.get("skin") not in (0, 1, 2, 3):
            rep.add("error", "avatar", f"{name}: skin باید ۰ تا ۳ باشد", "درست کن", base + ("avatar", "skin"))
        if g == "f" and av.get("hair") != "hijab":
            rep.add("error", "hijab", f"{name}: زن‌ها همیشه hair=\"hijab\" دارند", "hair را hijab کن", base + ("avatar", "hair"))
        if g == "m" and av.get("hair") == "hijab":
            rep.add("error", "hijab", f"{name}: مرد با hijab", "hair را درست کن", base + ("avatar", "hair"))
        por = av.get("portrait")
        if ports and por not in ports:
            rep.add("error", "portrait", f"{name}: پرتره‌ی «{por}» وجود ندارد",
                    "یکی از پرتره‌های فهرست پرامپت را بگذار (هم‌جنس و هم‌سن و هم‌شغل)", base + ("avatar", "portrait"))
        elif isinstance(por, str):
            if g in ("m", "f") and not por.startswith(g + "_"):
                rep.add("error", "portrait", f"{name}: پرتره‌ی «{por}» با جنسیت نمی‌خواند", "پرتره‌ی هم‌جنس بگذار", base + ("avatar", "portrait"))
            if por in seen_ports:
                rep.add("error", "portrait", f"پرتره‌ی «{por}» برای {name} و {seen_ports[por]} تکراری است",
                        "هر مظنون پرتره‌ی جدا دارد", base + ("avatar", "portrait"))
            seen_ports[por] = name


def check_evidence_solution(rep: Report, d: dict, story: bool):
    ev = d.get("evidence")
    sol = d.get("solution")
    sus = d.get("suspects") or []
    if isinstance(ev, list):
        _bound(rep, "evidence", len(ev), ("evidence",), "تعداد مدرک‌ها")
        types_n = 0
        for i, e in enumerate(ev):
            if not isinstance(e, dict):
                continue
            if e.get("id") != f"e{i + 1}":
                rep.add("warn", "eid", f"شناسه‌ی مدرک {fa(i + 1)} باید e{i + 1} باشد", f"id را e{i + 1} کن", ("evidence", i, "id"))
            if e.get("type") not in EVID_TYPES:
                rep.add("error", "etype", f"نوع مدرک {e.get('id')} باید یکی از {sorted(EVID_TYPES)} باشد", "type را درست کن", ("evidence", i, "type"))
            if e.get("type") in ("cctv", "phone", "forensic", "receipt"):
                types_n += 1
            if isinstance(e.get("title"), str):
                _bound(rep, "evidence.title", len(e["title"].strip()), ("evidence", i, "title"), f"مدرک {e.get('id')} / عنوان")
            if isinstance(e.get("text"), str):
                _bound(rep, "evidence.text", len(e["text"].strip()), ("evidence", i, "text"), f"مدرک {e.get('id')} / متن")
                if re.search(GUILT, e["text"]) or "اعتراف" in e["text"]:
                    rep.add("warn", "leak", f"مدرک {e.get('id')} واژه‌ی گناه/اعتراف دارد؛ نباید خودش جواب را بدهد",
                            "متن را توصیفیِ خنثی کن", ("evidence", i, "text"))
        if types_n > 2:
            rep.add("warn", "machine", f"{fa(types_n)} مدرک «ماشینی» (دوربین/گوشی/رسید/جنایی)؛ حداکثر ۲ تا", "مدرک‌های انسانی‌تر (سخن، شیء، سند) بگذار", ("evidence",))
    hints = d.get("hints")
    if isinstance(hints, list):
        if len(hints) != 3:
            rep.add("error", "hints", f"hints باید دقیقاً ۳ تا باشد ({fa(len(hints))})", "سه راهنمای پله‌ای بنویس", ("hints",))
        for i, h in enumerate(hints):
            if isinstance(h, str):
                _bound(rep, "hint", len(h.strip()), ("hints", i), f"راهنمای {fa(i + 1)}")
    if story and d.get("partner_hints") is not None:
        ph = d["partner_hints"]
        if not isinstance(ph, list) or len(ph) != 3:
            rep.add("error", "hints", "partner_hints باید ۳ متن باشد", "سه متن بنویس یا کلید را حذف کن", ("partner_hints",))
        else:
            for i, h in enumerate(ph):
                if isinstance(h, str):
                    _bound(rep, "hint", len(h.strip()), ("partner_hints", i), f"راهنمای ناصری {fa(i + 1)}")
    if not isinstance(sol, dict):
        return
    ids = {s.get("id"): s for s in sus if isinstance(s, dict)}
    cul = ids.get(sol.get("culprit"))
    proof = sol.get("proof") or []
    if isinstance(ev, list):
        if len(proof) < 2:
            rep.add("error", "proof", "proof باید دست‌کم ۲ مدرک باشد (ترکیب، نه یک کارت)", "دست‌کم دو مدرک ترکیبی بگذار", ("solution", "proof"))
        if len(proof) * 2 > len(ev):
            rep.add("error", "proof", f"proof ({fa(len(proof))}) بیش از نیمِ مدرک‌ها ({fa(len(ev))}) است", "فقط مدرک‌هایی که مستقیم گفته‌ی مجرم را نقض می‌کنند", ("solution", "proof"))
    if isinstance(sol.get("explanation"), str):
        _bound(rep, "explanation", len(sol["explanation"].strip()), ("solution", "explanation"), "توضیح راه‌حل")
        if cul:
            for s in sus:
                if s is cul or not isinstance(s, dict):
                    continue
                toks_s = [t for t in str(s.get("name", "")).split() if len(t) >= 3]
                if toks_s and not any(t in sol["explanation"] for t in toks_s):
                    rep.add("warn", "false_trail", f"توضیح راه‌حل درباره‌ی {s.get('name')} حرفی نزده؛ باید بگوید چرا مسیر غلط بود",
                            "برای هر مظنونِ بی‌گناه یک جمله بگذار", ("solution", "explanation"))
    # leaked answer
    if cul:
        full = str(cul.get("name", "")).strip()
        toks = [t for t in full.split() if len(t) >= 3]
        if isinstance(hints, list):
            for i, h in enumerate(hints):
                if isinstance(h, str) and any(_find_word(h, t) for t in [full, *toks]):
                    rep.add("error", "leak", "راهنما نام مجرم را می‌برد", "راهنما به تناقض اشاره کند نه به نام مجرم", ("hints", i))
        if story and isinstance(d.get("partner_hints"), list):
            for i, h in enumerate(d["partner_hints"]):
                if isinstance(h, str) and any(_find_word(h, t) for t in [full, *toks]):
                    rep.add("error", "leak", "راهنمای ناصری نام مجرم را می‌برد", "نام را حذف کن", ("partner_hints", i))
        for path, s in walk_strings(d):
            if kind_of(path) in ("id", "meta", "post") or path[0] in ("hints", "partner_hints") or path[0] == "solution":
                continue
            for sentence in re.split(r"[.؟!؛\n]", s):
                if re.search(GUILT, sentence) and any(_find_word(sentence, t) for t in [full, *toks]):
                    rep.add("error", "leak", f"جمله نام مجرم را با واژه‌ی گناه کنار هم دارد: «{sentence.strip()[:60]}»",
                            "جمله را بازنویسی کن تا گناه مجرم را لو ندهد", path)
                    break


def check_notify_free_common(rep: Report, d: dict):
    diff = d.get("difficulty")
    if diff not in (4, 5):
        rep.add("error", "difficulty", f"difficulty باید ۴ یا ۵ باشد ({diff})", "قانون: پرونده‌ی ساده نداریم", ("difficulty",))
    for key, lim in (("title", "title"), ("location", "location"), ("intro", "intro")):
        v = d.get(key)
        if isinstance(v, str):
            _bound(rep, lim, len(v.strip()), (key,), key)
        else:
            rep.add("error", "missing", f"{key} نیست", f"{key} را بنویس", ())


def check_top_keys(rep: Report, d: dict, allowed: set[str]):
    for k in d:
        if k not in allowed and k not in META_KEYS:
            rep.add("error", "extra_key", f"کلید اضافه‌ی «{k}» (به برنامه فرستاده می‌شود و ممکن است راه‌حل را لو بدهد)",
                    f"«{k}» را حذف کن", (k,))
    for k in sorted(allowed - {"partner_hints", "publish"} - set(d)):
        rep.add("error", "missing", f"کلید لازم «{k}» نیست", f"«{k}» را اضافه کن", ())


def run_server_validator(rep: Report, fn, *args):
    """Last gate: the server's own validator. Adds an error only if no earlier error exists (its message is single)."""
    try:
        fn(*args)
    except Exception as e:  # CaseError / KeyError / TypeError on malformed data
        if rep.ok:
            rep.add("error", "server", f"اعتبارسنج سرور رد کرد: {e}", "طبق پیام سرور اصلاح کن", ())


# ---------------------------------------------------------------------------------------------------------------
# story chapters
def _scene_graph(rep: Report, d: dict):
    scenes, ending = d.get("scenes"), d.get("ending")
    if not isinstance(scenes, list) or not scenes or not isinstance(ending, dict):
        rep.add("error", "scenes", "scenes (فهرست صحنه‌ها) یا ending نیست", "ساختار scenes/ending را مثل نمونه بنویس", ())
        return
    _bound(rep, "scenes", len(scenes), ("scenes",), "تعداد صحنه‌ها")
    eid = ending.get("id")
    if isinstance(ending.get("text"), str):
        _bound(rep, "ending.text", len(ending["text"].strip()), ("ending", "text"), "متن ending")
        for w in OUTCOME_WORDS:
            if w in ending["text"]:
                rep.add("warn", "outcome", f"ending نتیجه را می‌گوید («{w}»)", "ending فقط به بازجویی و اتهام برسد؛ نتیجه را ناصری بعد از اتهام می‌گوید", ("ending", "text"))
    ids = [s.get("id") for s in scenes if isinstance(s, dict)]
    for i in ids + [eid]:
        if not isinstance(i, str) or not SCENE_ID_RE.match(i):
            rep.add("error", "sceneid", f"شناسه‌ی نامعتبر «{i}» (فقط حرف لاتین/رقم/_ تا ۲۴ نویسه)", "id را درست کن", ("scenes",))
    if len(set(ids)) != len(ids) or eid in ids:
        rep.add("error", "sceneid", "شناسه‌ی صحنه‌ها تکراری است (یا با ending یکی است)", "هر صحنه id یکتا داشته باشد", ("scenes",))
    by_id = {s["id"]: s for s in scenes if isinstance(s, dict) and isinstance(s.get("id"), str)}
    board = d.get("board") if isinstance(d.get("board"), dict) else {}
    people = [p.get("id") for p in board.get("people", []) if isinstance(p, dict)]
    clue_ids = {c.get("id") for c in board.get("clues", []) if isinstance(c, dict)} | {e.get("id") for e in d.get("evidence", []) if isinstance(e, dict)}
    for j, c in enumerate(board.get("clues", [])):
        if isinstance(c, dict):
            if isinstance(c.get("title"), str):
                _bound(rep, "board.clue.title", len(c["title"].strip()), ("board", "clues", j, "title"), f"سرنخ {c.get('id')} / عنوان")
            if isinstance(c.get("text"), str):
                _bound(rep, "board.clue.text", len(c["text"].strip()), ("board", "clues", j, "text"), f"سرنخ {c.get('id')} / متن")
    nxt: dict[str, set] = {}
    branching = 0
    gives: dict[str, list] = {}
    for si, s in enumerate(scenes):
        if not isinstance(s, dict):
            continue
        sid = s.get("id")
        sp = ("scenes", si)
        if isinstance(s.get("text"), str):
            _bound(rep, "scene.text", words(s["text"]), sp + ("text",), f"صحنه {sid} / متن")
            if re.search(r"\be\d+\b", s["text"]):
                rep.add("warn", "idleak", f"صحنه {sid} شناسه‌ی فنی (e۱...) دارد", "شناسه‌ها فقط در JSON‌اند نه در متن", sp + ("text",))
        else:
            rep.add("error", "missing", f"صحنه {sid}: text نیست", "متن را بنویس", sp)
        opts = s.get("options")
        if not isinstance(opts, list) or not opts:
            rep.add("error", "dead_end", f"صحنه {sid} گزینه ندارد (بن‌بست)", "۲ تا ۳ گزینه بگذار", sp)
            nxt[sid] = set()
            continue
        _bound(rep, "scene.options", len(opts), sp + ("options",), f"صحنه {sid}: تعداد گزینه‌ها")
        oids = [o.get("id") for o in opts if isinstance(o, dict)]
        if len(set(oids)) != len(oids):
            rep.add("error", "optid", f"صحنه {sid}: id گزینه‌ها تکراری است", "id یکتا", sp + ("options",))
        nxt[sid] = set()
        for oi, o in enumerate(opts):
            if not isinstance(o, dict):
                continue
            op = sp + ("options", oi)
            if isinstance(o.get("title"), str):
                _bound(rep, "option.title", len(o["title"].strip()), op + ("title",), f"گزینه {o.get('id')} / title")
                if re.search(r"(درست|غلط|صحیح|اشتباه)", o["title"]):
                    rep.add("warn", "judgy", f"عنوان گزینه {o.get('id')} قضاوت می‌کند", "گزینه‌ها کار مشخص‌اند، نه درست/غلط", op + ("title",))
            else:
                rep.add("error", "missing", f"گزینه {o.get('id')}: title نیست", "title بنویس", op)
            if isinstance(o.get("sub", ""), str):
                _bound(rep, "option.sub", len(o.get("sub", "").strip()), op + ("sub",), f"گزینه {o.get('id')} / sub")
            g = o.get("goes_to")
            if g != eid and g not in by_id:
                rep.add("error", "goes_to", f"گزینه {o.get('id')} در صحنه {sid} به «{g}» می‌رود که وجود ندارد", "goes_to را به id یک صحنه یا ending بده", op + ("goes_to",))
            else:
                nxt[sid].add(g)
            for key in ("gives_clue", "needs_clue"):
                v = o.get(key)
                for c in ([v] if isinstance(v, str) else (v or [])):
                    if c not in clue_ids:
                        rep.add("error", "clue", f"گزینه {o.get('id')}: سرنخ «{c}» در board.clues یا evidence نیست", f"«{c}» را به board.clues اضافه کن یا درست کن", op + (key,))
            for c in ([o["gives_clue"]] if isinstance(o.get("gives_clue"), str) else (o.get("gives_clue") or [])):
                gives.setdefault(c, []).append((sid, g))
            for p, st in (o.get("relations") or {}).items():
                if p not in people or st not in ("unmet", "neutral", "friendly", "suspicious"):
                    rep.add("error", "relation", f"گزینه {o.get('id')}: رابطه‌ی نامعتبر {p}:{st}", "person باید در board.people باشد و state یکی از unmet/neutral/friendly/suspicious", op + ("relations",))
        if len({g for g in nxt[sid]}) >= 2:
            branching += 1
        if opts and all(isinstance(o, dict) and o.get("needs_clue") for o in opts):
            rep.add("error", "locked", f"صحنه {sid}: همه‌ی گزینه‌ها قفل‌اند", "دست‌کم یک گزینه بدون needs_clue", sp)
    if branching < 1:
        rep.add("error", "branch", "هیچ صحنه‌ای مسیر را دوشاخه نمی‌کند", "دست‌کم یک صحنه دو گزینه با مقصد متفاوت داشته باشد", ("scenes",))
    if not by_id:
        return
    first = scenes[0].get("id") if isinstance(scenes[0], dict) else None
    # reachability, loops, termination
    reach: dict[str, set] = {}
    visiting: set[str] = set()
    loop = [False]

    def walk(n):
        if n == eid or n not in by_id:
            return set()
        if n in visiting:
            loop[0] = True
            rep.add("error", "loop", f"صحنه‌ها دور می‌زنند (در {n})", "گزینه‌ها فقط به جلو بروند", ("scenes",))
            return set()
        if n in reach:
            return reach[n]
        visiting.add(n)
        out = set()
        for m in nxt.get(n, ()):
            out.add(m)
            out |= walk(m)
        visiting.discard(n)
        reach[n] = out
        return out

    below = walk(first)
    for sid in by_id:
        if sid != first and sid not in below:
            rep.add("error", "unreachable", f"صحنه {sid} از هیچ مسیری قابل‌رسیدن نیست", "گزینه‌ای به آن وصل کن یا حذفش کن", ("scenes",))
    if not loop[0]:
        for sid in by_id:
            if eid not in (reach.get(sid, set()) | nxt.get(sid, set())):
                rep.add("error", "no_end", f"صحنه {sid} هرگز به ending نمی‌رسد", "مسیرش را به ending برسان", ("scenes",))
        # a locked option's clue must be obtainable on a path before its scene
        for si, s in enumerate(scenes):
            if not isinstance(s, dict) or s.get("id") not in by_id:
                continue
            for oi, o in enumerate(s.get("options") or []):
                need = o.get("needs_clue") if isinstance(o, dict) else None
                for c in ([need] if isinstance(need, str) else (need or [])):
                    ok = False
                    for t in scenes:
                        if not isinstance(t, dict) or t.get("id") == s["id"] or s["id"] not in reach.get(t.get("id"), set()):
                            continue
                        for o2 in t.get("options") or []:
                            g2 = o2.get("gives_clue")
                            if c in ([g2] if isinstance(g2, str) else (g2 or [])) and (o2.get("goes_to") == s["id"] or s["id"] in reach.get(o2.get("goes_to"), set())):
                                ok = True
                    if not ok:
                        rep.add("error", "needs", f"گزینه {o.get('id')} سرنخ «{c}» می‌خواهد که پیش از این صحنه به دست نمی‌آید",
                                f"گزینه‌ای در صحنه‌ای قبلی که روی مسیر هست «{c}» را gives_clue بدهد", ("scenes", si, "options", oi, "needs_clue"))
    # fair relations: all «suspicious» on the culprit would point at the answer
    cul = {s.get("id"): s for s in d.get("suspects", []) if isinstance(s, dict)}.get((d.get("solution") or {}).get("culprit"))
    if cul:
        cname = str(cul.get("name", ""))
        target = [p.get("id") for p in board.get("people", []) if isinstance(p, dict) and str(p.get("name", "")).split()[:1] == cname.split()[:1]]
        sus_rel = [(p, st) for s in scenes if isinstance(s, dict) for o in s.get("options") or [] if isinstance(o, dict)
                   for p, st in (o.get("relations") or {}).items() if st == "suspicious"]
        if sus_rel and target and all(p in target for p, _ in sus_rel):
            rep.add("warn", "relation_leak", "تمام رابطه‌های «مشکوک» روی خودِ مجرم است و جواب را لو می‌دهد",
                    "رابطه‌ی مشکوک را بین چند نفر پخش کن", ("scenes",))
    rep.stats["scenes"] = len(scenes)
    rep.stats["branch_scenes"] = branching


SEASON_SPOILER_LOCK = 10  # the bible's truth may appear only in chapter 10


def check_season_secret(rep: Report, d: dict, chapter: int):
    if chapter >= SEASON_SPOILER_LOCK:
        return
    for path, s in walk_strings(d):
        if kind_of(path) in ("id", "meta"):
            continue
        if _find_word(s, "افشار") and (_find_word(s, "کاوه") or _find_word(s, "یدالله")):
            rep.add("error", "season_spoiler", "نام «افشار» کنار «کاوه/یدالله» راز فصل ۱۰ را لو می‌دهد", "این اشاره فقط در فصل ۱۰ مجاز است", path)
        for sentence in re.split(r"[.؟!؛\n]", s):
            if _find_word(sentence, "افشار") and re.search(r"(دزد|سارق|کبریتی|کبریت‌دزد)", sentence):
                rep.add("error", "season_spoiler", "خانم افشار پیش از فصل ۱۰ نباید به دزد وصل شود", "جمله را عوض کن", path)
                break
    for key in ("suspects",):
        for i, s in enumerate(d.get(key, [])):
            if isinstance(s, dict) and ("افشار" in str(s.get("name", "")) or "نرگس" in str(s.get("name", ""))):
                rep.add("error", "season_spoiler", "نرگس افشار پیش از فصل ۱۰ مظنون نیست", "مظنون دیگری بگذار", ("suspects", i, "name"))


def check_story_kit(rep: Report, d: dict, chapter: int, root: Path):
    kit = d.get("_kit")
    if not isinstance(kit, dict):
        rep.add("error", "kit", "بخش _kit (خلاصه برای پیام بعدی) نیست", "_kit را مثل نمونه اضافه کن", ())
        return
    if not isinstance(kit.get("summary"), str):
        rep.add("error", "kit", "_kit.summary نیست", "خلاصه‌ی ۲ تا ۴ جمله‌ای فصل را بنویس", ("_kit",))
    else:
        _bound(rep, "kit.summary", len(kit["summary"].strip()), ("_kit", "summary"), "_kit.summary")
    pt = kit.get("puzzle_type")
    if not isinstance(pt, int) or not 1 <= pt <= 10:
        rep.add("error", "kit", "_kit.puzzle_type باید عدد ۱ تا ۱۰ باشد (docs/case-writing-rules.md بخش ۲)", "درست کن", ("_kit", "puzzle_type"))
        return
    if kit.get("culprit_slot") != (d.get("solution") or {}).get("culprit"):
        rep.add("error", "kit", "_kit.culprit_slot با solution.culprit یکی نیست", "یکی کن", ("_kit", "culprit_slot"))
    ledger = load_kit(root, d.get("season") or 1)
    plan = ledger.get("plan", {}).get(str(chapter))
    if plan:
        if plan.get("type") != pt:
            rep.add("warn", "plan", f"نوع معما {fa(pt)} است؛ طرح بایبل برای فصل {fa(chapter)}: {fa(plan['type'])}", "با بایبل یکی کن یا دلیل داشته باش", ("_kit", "puzzle_type"))
        if plan.get("culprit") != (d.get("solution") or {}).get("culprit"):
            rep.add("warn", "plan", f"مجرم در s{plan['culprit'][1:]} برنامه‌ریزی شده (بایبل)", "اسلات مجرم را با بایبل یکی کن", ("solution", "culprit"))
        if plan.get("scene") and plan["scene"] != d.get("scene"):
            rep.add("warn", "plan", f"صحنه‌ی بایبل برای این فصل «{plan['scene']}» است", "scene را یکی کن", ("scene",))
    done = {int(k): v for k, v in ledger.get("chapters", {}).items() if int(k) != chapter}
    prev = done.get(chapter - 1)
    if prev and prev.get("type") == pt:
        rep.add("error", "type_repeat", "نوع معما با فصل قبل یکی است؛ دو فصل پشت‌سرهم نوع یکسان ندارند", "نوع دیگری از فهرست ۱۰تایی بگیر", ("_kit", "puzzle_type"))
    if sum(1 for v in done.values() if v.get("type") == pt) >= 2:
        rep.add("error", "type_repeat", f"نوع معما {fa(pt)} پیش‌تر دو بار آمده؛ بیش از ۲ بار در یک فصل‌چین مجاز نیست", "نوع دیگر", ("_kit", "puzzle_type"))
    if prev and prev.get("culprit") == (d.get("solution") or {}).get("culprit"):
        rep.add("warn", "slot_repeat", "مجرم در همان اسلات فصل قبل است", "اسلات مجرم را عوض کن", ("solution", "culprit"))


def validate_story_dict(d: dict, chapter: int | None = None, root: Path = ROOT) -> Report:
    rep = Report()
    if not isinstance(d, dict):
        rep.add("error", "shape", "ریشه‌ی JSON باید یک شیء { } باشد", "فقط یک شیء JSON بده", ())
        return rep
    content = load_content(root)
    m = re.match(r"^s(\d{2})ch(\d{2})$", str(d.get("id", "")))
    if not m:
        rep.add("error", "id", f"id باید مثل s01ch02 باشد (الان «{d.get('id')}»)", "id را درست کن", ("id",))
        return rep
    season, ch = int(m.group(1)), int(m.group(2))
    if chapter is not None and ch != chapter:
        rep.add("error", "id", f"این فایل برای فصل {fa(chapter)} خواسته شده ولی id فصل {fa(ch)} است", "id/number/chapter را یکی کن", ("id",))
    if d.get("season") != season or d.get("chapter") != ch or d.get("number") != ch:
        rep.add("error", "id", "season/chapter/number با id یکی نیست", f"season={season}, chapter={ch}, number={ch}", ("number",))
    check_top_keys(rep, d, TOP_STORY)
    check_notify_free_common(rep, d)
    if d.get("scene") not in content.SCENES:
        rep.add("error", "scene", f"scene «{d.get('scene')}» در فهرست نیست", f"یکی از: {', '.join(sorted(content.SCENES))}", ("scene",))
    for key, lim in (("partner_intro", "partner_intro"), ("partner_outro_win", "partner_outro"),
                     ("partner_outro_lose", "partner_outro"), ("thread", "thread")):
        v = d.get(key)
        if isinstance(v, str) and v.strip():
            _bound(rep, lim, len(v.strip()), (key,), key)
        else:
            rep.add("error", "missing", f"{key} نیست", f"{key} را به صدای ناصری بنویس", ())
    check_suspects(rep, d, root)
    check_evidence_solution(rep, d, story=True)
    _scene_graph(rep, d)
    check_text_rules(rep, d, story=True)
    check_season_secret(rep, d, ch)
    check_story_kit(rep, d, ch, root)
    # server gate (on a copy: it may add a default `publish`)
    if not rep.errors:
        copy = json.loads(json.dumps(d, ensure_ascii=False))
        for k in META_KEYS:
            copy.pop(k, None)
        run_server_validator(rep, content.validate_story, copy, season, ch)
    rep.stats["chapter"] = ch
    return rep


# ---------------------------------------------------------------------------------------------------------------
# daily cases
def case_log_types(root: Path = ROOT) -> list[tuple[str, int]]:
    p = root / "docs" / "case-log.md"
    out = []
    if p.is_file():
        for line in p.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\|\s*(c\d{3})\b[^|]*\|[^|]*\|\s*(\d+)", line)
            if m:
                out.append((m.group(1), int(m.group(2))))
    return sorted(out)


def validate_case_dict(d: dict, root: Path = ROOT) -> Report:
    rep = Report()
    if not isinstance(d, dict):
        rep.add("error", "shape", "ریشه‌ی JSON باید یک شیء { } باشد", "فقط یک شیء JSON بده", ())
        return rep
    content = load_content(root)
    if not re.match(r"^c\d{3}$", str(d.get("id", ""))):
        rep.add("error", "id", f"id باید مثل c041 باشد (الان «{d.get('id')}»)", "id را درست کن", ("id",))
    elif d.get("number") != int(d["id"][1:]):
        rep.add("error", "id", "number با id یکی نیست", "number را عدد id بگذار", ("number",))
    check_top_keys(rep, d, TOP_CASE)
    check_notify_free_common(rep, d)
    try:
        import datetime
        datetime.date.fromisoformat(str(d.get("publish")))
    except ValueError:
        rep.add("error", "publish", "publish باید تاریخ YYYY-MM-DD باشد", "درست کن", ("publish",))
    if d.get("scene") not in content.SCENES:
        rep.add("error", "scene", f"scene «{d.get('scene')}» در فهرست نیست", f"یکی از: {', '.join(sorted(content.SCENES))}", ("scene",))
    check_suspects(rep, d, root)
    check_evidence_solution(rep, d, story=False)
    check_text_rules(rep, d, story=False)
    # notify teaser
    nt = d.get("_notify")
    if not isinstance(nt, dict) or not all(isinstance(nt.get(k), str) for k in ("head", "body")):
        rep.add("error", "notify", "بخش _notify {head, body} نیست", "تیزر اعلان را مثل نمونه اضافه کن", ())
    else:
        _bound(rep, "notify.head", len(nt["head"].strip()), ("_notify", "head"), "_notify.head")
        _bound(rep, "notify.body", len(nt["body"].strip()), ("_notify", "body"), "_notify.body")
        nf = cases_dir(root).parent / "notify.json"
        if nf.is_file():
            heads = {k: v.get("head") for k, v in json.loads(nf.read_text(encoding="utf-8")).items() if k != d.get("id")}
            if nt["head"].strip() in heads.values():
                rep.add("error", "notify", "head اعلان با یکی از پرونده‌های دیگر یکی است", "head یکتا بنویس", ("_notify", "head"))
    kit = d.get("_kit")
    if not isinstance(kit, dict) or not isinstance(kit.get("puzzle_type"), int) or not 1 <= kit["puzzle_type"] <= 10:
        rep.add("error", "kit", "_kit.puzzle_type (۱ تا ۱۰) نیست", "نوع معمای اصلی را بنویس", ())
    else:
        if kit.get("culprit_slot") != (d.get("solution") or {}).get("culprit"):
            rep.add("error", "kit", "_kit.culprit_slot با solution.culprit یکی نیست", "یکی کن", ("_kit", "culprit_slot"))
        hist = [(c, t) for c, t in case_log_types(root) if c != d.get("id")]
        if hist and hist[-1][1] == kit["puzzle_type"]:
            rep.add("error", "type_repeat", f"نوع معما با {hist[-1][0]} (آخرین پرونده) یکی است", "نوع دیگر", ("_kit", "puzzle_type"))
    # id / date must be free
    if re.match(r"^c\d{3}$", str(d.get("id", ""))):
        if (cases_dir(root) / f"{d['id']}.json").is_file():
            rep.add("warn", "exists", f"{d['id']} از قبل هست؛ وارد کردن با --replace جایش را می‌گیرد", "شماره‌ی بعدی را بگیر", ("id",))
    if not rep.errors:
        copy = json.loads(json.dumps(d, ensure_ascii=False))
        for k in META_KEYS:
            copy.pop(k, None)
        run_server_validator(rep, content.validate, copy)
    return rep


# ---------------------------------------------------------------------------------------------------------------
# reports
def attach_lines(rep: Report, lines: dict):
    for i in rep.issues:
        p = i.path
        while p and p not in lines:
            p = p[:-1]
        i.line = lines.get(p, 0)


def format_report(rep: Report, d, title: str, notes=(), show_warnings=True) -> str:
    err, warn = rep.errors, rep.warnings
    out = [f"══ {title} ══"]
    out += [f"• {n}" for n in notes]
    out.append(f"نتیجه: {'✓ قبول' if rep.ok else '✗ رد'}  —  {fa(len(err))} خطا، {fa(len(warn))} هشدار"
               + (f"  |  {fa(rep.stats.get('scenes', 0))} صحنه، {fa(rep.stats.get('branch_scenes', 0))} دوشاخه" if "scenes" in rep.stats else ""))

    def one(n, i):
        where = render_path(d, i.path) if isinstance(d, (dict, list)) and i.path else "—"
        ln = f"خط {fa(i.line)} | " if i.line else ""
        tag = " [خودکار]" if i.auto else ""
        return f" {fa(n)}. {ln}{where}{tag}\n      مشکل: {i.msg}\n      اصلاح: {i.fix}"

    if err:
        out.append("\nخطاها (باید اصلاح شوند):")
        out += [one(n, i) for n, i in enumerate(err, 1)]
    if warn and show_warnings:
        out.append("\nهشدارها (بهتر است اصلاح شوند؛ مورد «خودکار» را ایمپورتر خودش درست می‌کند):")
        out += [one(n, i) for n, i in enumerate(warn, 1)]
    return "\n".join(out)


def build_fix_message(rep: Report, d, kind: str = "فصل", include_warnings: bool = False, limit: int = 25) -> str:
    """The «اصلاحیه»: a ready message Amin pastes back to ChatGPT."""
    items = rep.errors + ([i for i in rep.warnings if not i.auto] if include_warnings else [])
    if not items:
        return ""
    lines = ["FIX:",
             f"اصلاحیه‌ی {kind}. فقط موارد زیر را اصلاح کن و بقیه‌ی JSON را کاملاً بدون تغییر نگه دار "
             "(همان id ها، همان ترتیب، همان متن‌های سالم). "
             "پیش از ارسال چک‌لیست «SELF-CHECK» را دوباره اجرا کن. "
             "خروجی: کل JSON اصلاح‌شده، فقط JSON خام، بدون توضیح و بدون ```.", ""]
    for n, i in enumerate(items[:limit], 1):
        where = render_path(d, i.path) if i.path else "ساختار کلی"
        ln = f"خط {fa(i.line)}، " if i.line else ""
        lines.append(f"{fa(n)}) {ln}{where}\n   مشکل: {i.msg}\n   اصلاح: {i.fix}")
    if len(items) > limit:
        lines.append(f"... و {fa(len(items) - limit)} مورد دیگر (بعد از این‌ها دوباره بررسی می‌کنم).")
    return "\n".join(lines)


def next_context(d: dict) -> str:
    """The block Amin pastes into the next «WRITE CHAPTER N+1» message (keeps ChatGPT's context small)."""
    kit = d.get("_kit") or {}
    ch = d.get("chapter")
    return (f"فصل {fa(ch)} «{d.get('title')}» — نوع معما {fa(kit.get('puzzle_type', '؟'))}، مجرم {kit.get('culprit_slot', '؟')}\n"
            f"خلاصه: {kit.get('summary', '').strip()}\n"
            f"رشته (thread): {str(d.get('thread', '')).strip()}")


# ---------------------------------------------------------------------------------------------------------------
# one entry point for the command-line tools
def check_text(raw: str, kind: str = "story", chapter: int | None = None, root: Path = ROOT):
    """Validate the raw text of a ChatGPT reply. Returns (report, object_or_None, notes)."""
    text, notes = extract_json(raw)
    try:
        obj, lines = parse_json_lines(text)
    except JsonLineError as e:
        rep = Report()
        rep.add("error", "json", f"JSON خراب است: {e}", "کل JSON را دوباره و کامل بفرست؛ فقط یک شیء JSON معتبر، بدون ویرگول اضافه", ())
        rep.issues[0].line = e.line
        return rep, None, notes
    rep = validate_story_dict(obj, chapter, root) if kind == "story" else validate_case_dict(obj, root)
    attach_lines(rep, lines)
    if notes:
        rep.add("warn", "wrapper", "؛ ".join(notes) + " (شماره‌ی خط‌ها نسبت به خود JSON است)", "نیازی به اصلاح نیست؛ فقط یادآوری که پرامپت «فقط JSON خام» می‌خواهد", (), auto=True)
    return rep, obj, notes


def read_input(path: str) -> str:
    return sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")


def write_json(path: Path, obj, newline: bool = True):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + ("\n" if newline else ""), encoding="utf-8")


def strip_meta(obj: dict) -> dict:
    return {k: v for k, v in obj.items() if k not in META_KEYS}
