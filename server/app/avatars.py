"""Profile avatars and frames (docs/avatars-plan.md). The server is the boss of what a player owns.

Three ways to get one: free (everyone), a goal (unlocked by itself, kept forever) or the coin shop (bought once).
Goals watch a number about the player, like achievements do. Prices live in economy.py.
"""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from . import economy as eco
from .models import Player, PlayerAvatar, StoryProgress

FREE_AVATARS = 10                # det_01 .. det_10 (the images shipped with the app)
DEFAULT_FRAME = "frame_brass"


@dataclass(frozen=True)
class Item:
    id: str
    kind: str                    # avatar | frame
    title: str
    story: str
    how: str                     # free | goal | shop
    rarity: str = "common"       # common | rare | epic | legendary
    metric: str = ""             # for goals
    target: int = 0
    goal: str = ""               # the goal in words
    price: int = 0


def _free() -> list[Item]:
    return [Item(f"det_{i:02d}", "avatar", f"کارآگاه {i}", "", "free") for i in range(1, FREE_AVATARS + 1)]


AVATARS: list[Item] = _free() + [
    Item("ex_rookie", "avatar", "کارآگاه تازه‌نفس", "اولین نشانش را تازه گرفته و هنوز بوی تازگی می‌دهد.", "goal", "rare",
         "cases_solved", 10, "۱۰ پرونده حل کن"),
    Item("ex_nightowl", "avatar", "شب‌زنده‌دار", "چراغش تا صبح روشن است و باران هم خسته‌اش نمی‌کند.", "goal", "rare",
         "best_streak", 7, "۷ شب پشت سر هم پرونده‌ی روز را حل کن"),
    Item("ex_ironstreak", "avatar", "زنجیره‌ی آهنین", "حلقه به حلقه، شب به شب؛ زنجیرش هیچ‌وقت پاره نمی‌شود.", "goal", "epic",
         "best_streak", 30, "۳۰ شب پشت سر هم پرونده‌ی روز را حل کن"),
    Item("ex_threestar", "avatar", "سه‌پلاکِ واقعی", "روی سینه‌اش سه پلاک، و هر کدام را با دقت گرفته.", "goal", "epic",
         "case_3stars", 25, "۲۵ پرونده را با ۳ پلاک حل کن"),
    Item("ex_nohint", "avatar", "چشم‌تیز", "ذره‌بینش را فقط برای تماشا دارد؛ سرنخ نمی‌خواهد.", "goal", "rare",
         "case_no_hint", 10, "۱۰ پرونده را بدون خریدن سرنخ حل کن"),
    Item("ex_weekend", "avatar", "استاد آخر هفته", "قهوه، تخته‌ی پرونده و یک معمای بزرگ؛ همین.", "goal", "rare",
         "weekly_solved", 3, "۳ پرونده‌ی آخر هفته را حل کن"),
    Item("ex_partner", "avatar", "شریک ناصری", "سایه‌ای پشت سرش ایستاده که همه‌چیز را می‌داند.", "goal", "epic",
         "story_chapter", 5, "فصل ۵ داستان را تمام کن"),
    Item("ex_champion", "avatar", "قهرمان هفته", "تاج برگ و جام؛ هفته را او برد.", "goal", "legendary",
         "weekly_top3", 1, "جزو ۳ کارآگاه اول هفته شو"),
    Item("ex_alchemist", "avatar", "پیرِ کیمیاگر", "آزمایشگاهش پر از رازهایی است که هنوز کسی نفهمیده.", "shop", "epic",
         price=eco.AVATAR_PRICE["ex_alchemist"]),
    Item("ex_journalist", "avatar", "خبرنگار شب", "دوربین و دفترچه؛ خبر اول را همیشه او می‌گیرد.", "shop", "epic",
         price=eco.AVATAR_PRICE["ex_journalist"]),
    Item("ex_qajar", "avatar", "بازرس دوران قاجار", "کلاه فینه و سبیل پرپشت؛ از زمانی که پرونده‌ها با شمع خوانده می‌شد.", "shop", "epic",
         price=eco.AVATAR_PRICE["ex_qajar"]),
    Item("ex_cat", "avatar", "بازرس و گربه‌ی سیاه", "گربه‌اش همیشه یک قدم جلوتر از مظنون است.", "shop", "epic",
         price=eco.AVATAR_PRICE["ex_cat"]),
    Item("ex_chef", "avatar", "سرآشپز سایه‌ها", "چاقویش را فقط برای آشپزی نگه نمی‌دارد.", "shop", "epic",
         price=eco.AVATAR_PRICE["ex_chef"]),
    Item("ex_shadow", "avatar", "بازرس سایه", "کسی چهره‌اش را ندیده، ولی همه جواب‌هایش را دیده‌اند.", "shop", "legendary",
         price=eco.AVATAR_PRICE["ex_shadow"]),
    Item("ex_diva", "avatar", "ستاره‌ی صحنه‌ی نوآر", "نور روی او می‌ماند، حتی وقتی چراغ‌ها خاموش می‌شود.", "shop", "legendary",
         price=eco.AVATAR_PRICE["ex_diva"]),
    Item("ex_gold", "avatar", "کارآگاه طلایی", "کت سرمه‌ای و منگوله‌های زر؛ بالاترین نشان شهر.", "shop", "legendary",
         price=eco.AVATAR_PRICE["ex_gold"]),
]

FRAMES: list[Item] = [
    Item("frame_brass", "frame", "برنجی", "حلقه‌ی ساده‌ی برنجی، برای همه.", "free"),
    Item("frame_bronze", "frame", "برنزی", "نشان کارآگاهِ باتجربه.", "goal", "rare", "rank", 3, "به درجه‌ی «کارآگاه» برس"),
    Item("frame_silver", "frame", "نقره‌ای", "نشان سربازرس‌ها.", "goal", "epic", "rank", 6, "به درجه‌ی «سربازرس» برس"),
    Item("frame_gold", "frame", "طلایی", "چهار الماس برای افسانه‌ها.", "goal", "legendary", "rank", 9, "به درجه‌ی «افسانه» برس"),
    Item("frame_ember", "frame", "اخگر", "شعله‌ای که شب‌های پیاپی روشن مانده.", "goal", "epic", "best_streak", 14,
         "۱۴ شب پشت سر هم پرونده‌ی روز را حل کن"),
    Item("frame_tape", "frame", "نوار پلیس", "نوار زرد و مشکی دور صحنه‌ی ۵۰ پرونده.", "goal", "epic", "cases_solved", 50,
         "۵۰ پرونده حل کن"),
    Item("frame_loupe", "frame", "ذره‌بین طلایی", "برای ۳ کارآگاه اول هفته.", "goal", "legendary", "weekly_top3", 1,
         "جزو ۳ کارآگاه اول هفته شو"),
    Item("frame_fingerprint", "frame", "اثر انگشت", "حلقه‌ای از خط‌های شکسته‌ی اثر انگشت.", "shop", "rare",
         price=eco.FRAME_PRICE["frame_fingerprint"]),
    Item("frame_blinds", "frame", "پرده‌ی کرکره‌ای", "نور نوآر از لابه‌لای کرکره.", "shop", "rare",
         price=eco.FRAME_PRICE["frame_blinds"]),
    Item("frame_cuffs", "frame", "دستبند", "زنجیر و دستبند؛ مظنون فرار نمی‌کند.", "shop", "epic",
         price=eco.FRAME_PRICE["frame_cuffs"]),
    Item("frame_stamp", "frame", "مهر «حل شد»", "مهر قرمز پایان هر پرونده.", "shop", "epic",
         price=eco.FRAME_PRICE["frame_stamp"]),
    Item("frame_neon", "frame", "نئون", "دو حلقه‌ی نور فیروزه‌ای و ارغوانی.", "shop", "epic",
         price=eco.FRAME_PRICE["frame_neon"]),
    Item("frame_royal", "frame", "سلطنتی", "حلقه‌ی زر، تاج و جواهر.", "shop", "legendary",
         price=eco.FRAME_PRICE["frame_royal"]),
]
BY_ID = {i.id: i for i in AVATARS + FRAMES}
FREE_IDS = {i.id for i in AVATARS + FRAMES if i.how == "free"}


def avatar_key(p: Player) -> str:
    """The avatar id to show: the chosen one, or (old profiles) the portrait from the old index."""
    return p.avatar_id or f"det_{(p.avatar or 0) % FREE_AVATARS + 1:02d}"


def frame_key(p: Player) -> str:
    return p.avatar_frame if p.avatar_frame in BY_ID else DEFAULT_FRAME


def metrics(p: Player, story_chapter: int = 0) -> dict[str, int]:
    st = p.stats or {}
    return {"cases_solved": p.cases_solved or 0, "best_streak": max(p.best_streak or 0, p.streak or 0),
            "rank": eco.rank_of(p.xp or 0) + 1, "case_3stars": int(st.get("case_3stars", 0)),
            "case_no_hint": int(st.get("case_no_hint", 0)), "weekly_solved": int(st.get("weekly_solved", 0)),
            "weekly_top3": int(st.get("weekly_top3", 0)), "story_chapter": story_chapter}


async def story_chapter_done(session: AsyncSession, p: Player) -> int:
    """The highest finished story chapter of season 1 (0 if none)."""
    rows = (await session.execute(select(StoryProgress.chapter).where(
        StoryProgress.player_id == p.id, StoryProgress.season == 1, StoryProgress.finished_at.is_not(None)))).scalars().all()
    return max(rows, default=0)


async def owned_rows(session: AsyncSession, p: Player) -> dict[tuple[str, str], str]:
    rows = (await session.execute(select(PlayerAvatar.kind, PlayerAvatar.avatar_id, PlayerAvatar.how).where(
        PlayerAvatar.player_id == p.id))).all()
    return {(k, a): h for k, a, h in rows}


async def grant(session: AsyncSession, p: Player, item: Item, how: str) -> bool:
    """Adds the item for the player. False if they already had it (safe when two requests race)."""
    dialect = session.bind.dialect.name if session.bind is not None else "sqlite"
    insert = pg_insert if dialect == "postgresql" else sqlite_insert
    res = await session.execute(insert(PlayerAvatar).values(
        player_id=p.id, kind=item.kind, avatar_id=item.id, how=how).on_conflict_do_nothing(
        index_elements=["player_id", "kind", "avatar_id"]))
    return bool(res.rowcount)


async def check_goals(session: AsyncSession, p: Player, gains) -> None:
    """Unlocks every goal avatar/frame whose number is reached (kept forever). Caller commits."""
    owned = await owned_rows(session, p)
    pending = [i for i in AVATARS + FRAMES if i.how == "goal" and (i.kind, i.id) not in owned]
    if not pending:
        return
    chapter = await story_chapter_done(session, p) if any(i.metric == "story_chapter" for i in pending) else 0
    m = metrics(p, chapter)
    for i in pending:
        if m[i.metric] >= i.target and await grant(session, p, i, "goal"):
            gains.avatars.append({"id": i.id, "kind": i.kind, "title": i.title})


def catalog(p: Player, owned: dict[tuple[str, str], str], chapter: int) -> dict:
    m = metrics(p, chapter)
    cur_avatar, cur_frame = avatar_key(p), frame_key(p)

    def row(i: Item) -> dict:
        have = i.how == "free" or (i.kind, i.id) in owned
        out = {"id": i.id, "title": i.title, "story": i.story, "rarity": i.rarity, "how": i.how, "price": i.price,
               "owned": have, "equipped": i.id == (cur_avatar if i.kind == "avatar" else cur_frame)}
        if i.how == "goal":
            out["goal"] = i.goal
            out["target"] = i.target
            out["progress"] = i.target if have else min(i.target, m[i.metric])
        return out

    return {"coins": p.coins, "avatar": cur_avatar, "frame": cur_frame,
            "avatars": [row(i) for i in AVATARS], "frames": [row(i) for i in FRAMES]}
