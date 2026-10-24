"""«آلبوم مجرم‌ها»: every case a player solves puts its culprit into an album as a collectible card.

One place for everything the album knows:
- `group_of(data)`: which group a case belongs to. TODAY this is the case's `category` (scene as a fallback for a case
  without one). Change ONLY this function to regroup the album later; nothing else looks at categories or scenes.
- `skeleton()`: the cases published so far (shared by all players, cached per worker, no player data).
- `cards()`: one player's album, built from their CaseProgress rows. An unsolved case is a silhouette: no title, no
  culprit, nothing that could spoil it (tests/test_album.py checks the abuse path).
- `groups_done()` / `refresh_stat()`: completed groups. The reward is a permanent cosmetic FRAME from the avatar system
  (goal metric `album_groups`, granted by `avatars.check_goals`, which is an insert-or-ignore: once, idempotent, atomic).
  Never coins, warrants or avatars that are sold.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import content
from .cache import TTLCache
from .models import CaseProgress, Player

GROUP_MIN = 2          # a group of one case would be "complete" for free: it does not count for the reward
MAX_CARDS = 600        # hard bound on the answer, whatever the content grows to

SCENE_NAMES = {
    "bazaar_night": "بازار شب", "office": "دفتر کار", "train": "قطار", "museum": "موزه", "villa_rain": "ویلا زیر باران",
    "warehouse": "انبار", "harbor": "بندر", "hospital": "بیمارستان", "library": "کتابخانه", "theater": "تئاتر",
    "hotel": "هتل", "kitchen": "آشپزخانه", "snow_lodge": "کلبه‌ی برفی", "desert": "کویر", "subway": "مترو",
    "lab": "آزمایشگاه", "wedding": "عروسی", "school": "مدرسه", "airport": "فرودگاه", "tower": "برج",
}


def group_of(data: dict) -> tuple[str, str, str]:
    """(key, Persian title, icon name) of the album group a case belongs to. The ONE place that decides it."""
    cat = data.get("category", "")
    if cat in content.CATEGORIES:
        name, icon = content.CATEGORIES[cat]
        return f"cat:{cat}", name, icon
    scene = data.get("scene", "")
    return f"scene:{scene}", SCENE_NAMES.get(scene, "پرونده‌های دیگر"), "place"


_skeleton = TTLCache("album_cases", ttl=30, max_size=2)


async def skeleton() -> tuple:
    """The cases published so far (daily and weekend, no story chapters), oldest first. Same for every player, so it is
    shared per worker; it is dropped when the next case opens (content.next_boundary). It holds the Case objects the
    content module already keeps in memory; nothing from them is sent unless the player solved that case."""
    now = content.now_local()

    async def load():
        cases = list(content.opened(now)) + [c for c in content.weekly_cases() if content.opens_at(c) <= now]
        cases.sort(key=lambda c: (c.publish, c.id))
        return tuple(cases[:MAX_CARDS])

    return await _skeleton.get_or_load("k", load, now_wall=now, valid_until_of=lambda _v: content.next_boundary(now))


def groups_done(cases, solved_ids) -> int:
    """Groups of at least GROUP_MIN cases whose cases are ALL solved."""
    totals: dict[str, list[int]] = {}
    for c in cases:
        t = totals.setdefault(group_of(c.data)[0], [0, 0])
        t[0] += 1
        t[1] += c.id in solved_ids
    return sum(1 for total, got in totals.values() if total >= GROUP_MIN and got == total)


async def solved_ids(session: AsyncSession, player_id: str) -> set[str]:
    return set((await session.execute(select(CaseProgress.case_id).where(
        CaseProgress.player_id == player_id, CaseProgress.solved.is_(True)))).scalars().all())


async def refresh_stat(session: AsyncSession, player: Player) -> int:
    """Raises stats['album_groups'] to the number of groups completed now (never lowers it: a new case published later
    must not take a reward away). The caller commits."""
    from . import progress  # late: progress imports this module
    n = groups_done(await skeleton(), await solved_ids(session, player.id))
    progress.set_stat_max(player, "album_groups", n)
    return n


def culprit_card(c) -> dict:
    s = next(x for x in c.data["suspects"] if x["id"] == c.culprit)
    return {"name": s["name"], "role": s["role"], "avatar": s["avatar"]}


def entry(c, p: CaseProgress | None, *, openable: bool, price: int) -> dict:
    """One album slot. ONLY a case the player solved gets title, culprit and line; all other slots are silhouettes."""
    key, _name, _icon = group_of(c.data)
    out = {"id": c.id, "number": c.number, "group": key, "weekend": content.is_weekly(c.id), "solved": bool(p and p.solved)}
    if out["solved"]:
        s = next(x for x in c.data["suspects"] if x["id"] == c.culprit)
        out.update(title=c.data["title"], location=c.data["location"], stars=p.stars, culprit=culprit_card(c),
                   line=s["intro"].strip())
    else:
        out.update(stars=0, open=openable, price=0 if openable else price, failed=bool(p and p.failed))
    return out
