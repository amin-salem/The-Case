"""«پیشنهاد برای تو»: up to 3 archive cases the player has not solved, each with ONE real reason.

Reasons (a reason is used only when its real numbers pass a minimum sample, otherwise it is dropped; fewer than three
picks is fine and none means the app shows no section):
- `easy`    «آسان»: difficulty 1-2 and a real solve rate of at least EASY_RATE_PCT over at least MIN_PLAYERS detectives.
- `popular` «پرطرفدار»: the best real rating (average >= POPULAR_STARS over >= MIN_PLAYERS ratings), or else the most solves
            in the last 30 days (>= MIN_PLAYERS detectives).
- `taste`   «سلیقه‌ی تو»: a topic (category) where this player already solved at least TASTE_SOLVED cases, and a case of that
            topic that at least MIN_PLAYERS detectives have played.

Cost (2 workers, docs/operations.md «Capacity»): the per-case numbers are ONE aggregate shared by every player (cached,
bounded, TTL), the ratings come from the existing shared summary, and the only per-player read is the caller's own
progress rows (indexed on player_id). Nothing per player is kept in memory, so a new solve shows at once.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import case as sql_case
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .cache import TTLCache
from .models import CaseProgress, utcnow

MIN_PLAYERS = 20       # no reason is shown from fewer real detectives than this
EASY_MAX_DIFFICULTY = 2
EASY_RATE_PCT = 60     # at least this share of the detectives who played it solved it
POPULAR_STARS = 4.0
TASTE_SOLVED = 2       # solved cases of a topic before it counts as the player's taste
RECENT_DAYS = 30
MAX_PICKS = 3

_stats = TTLCache("case_pick_stats", ttl=120, max_size=2)


@dataclass(frozen=True)
class CaseStat:
    players: int = 0      # detectives who played it (opened, solved or lost it)
    solved: int = 0
    recent: int = 0       # solved in the last 30 days


async def case_stats(session: AsyncSession, now: datetime | None = None) -> dict[str, CaseStat]:
    """case_id -> CaseStat: one GROUP BY over case_progress, the same for everybody, shared for 2 minutes per worker."""
    async def load():
        cut = (now or utcnow()) - timedelta(days=RECENT_DAYS)
        P = CaseProgress
        played = (P.unlocked.is_(True)) | (P.solved.is_(True)) | (P.failed.is_(True))
        rows = (await session.execute(
            select(P.case_id,
                   func.sum(sql_case((played, 1), else_=0)),
                   func.sum(sql_case((P.solved.is_(True), 1), else_=0)),
                   func.sum(sql_case(((P.solved.is_(True)) & (P.finished_at >= cut), 1), else_=0)))
            .group_by(P.case_id))).all()
        return {cid: CaseStat(int(n or 0), int(s or 0), int(r or 0)) for cid, n, s, r in rows}
    return await _stats.get_or_load("s", load)


def clear() -> None:
    _stats.clear()


def choose(candidates: list[dict], solved_categories: dict[str, int], stats: dict[str, CaseStat],
           ratings: dict[str, tuple[float, int, int]]) -> list[dict]:
    """Pure choice. `candidates`: {id, number, category, difficulty} of the unsolved, not-lost archive cases.
    Returns up to MAX_PICKS dicts {case_id, reason, ...the real numbers behind the reason}, one case once."""
    def st(c):
        return stats.get(c["id"], CaseStat())

    def rate(c):
        s = st(c)
        return s.solved * 100 // s.players if s.players else 0

    easy = sorted((c for c in candidates if c["difficulty"] <= EASY_MAX_DIFFICULTY and st(c).players >= MIN_PLAYERS
                   and rate(c) >= EASY_RATE_PCT), key=lambda c: (-rate(c), -st(c).players, -c["number"]))
    rated = sorted((c for c in candidates if ratings.get(c["id"], (0.0, 0, 0))[1] >= MIN_PLAYERS
                    and ratings[c["id"]][0] >= POPULAR_STARS),
                   key=lambda c: (-ratings[c["id"]][0], -ratings[c["id"]][1], -c["number"]))
    recent = sorted((c for c in candidates if st(c).recent >= MIN_PLAYERS), key=lambda c: (-st(c).recent, -c["number"]))
    liked = [k for k, n in sorted(solved_categories.items(), key=lambda kv: (-kv[1], kv[0])) if k and n >= TASTE_SOLVED]
    taste: list[dict] = []
    for k in liked:
        taste += sorted((c for c in candidates if c["category"] == k and st(c).players >= MIN_PLAYERS),
                        key=lambda c: (-ratings.get(c["id"], (0.0, 0, 0))[0], -st(c).solved, -c["number"]))

    out: list[dict] = []
    used: set[str] = set()

    def take(reason: str, pool: list[dict], extra) -> None:
        for c in pool:
            if c["id"] not in used:
                used.add(c["id"])
                out.append({"case_id": c["id"], "reason": reason, **extra(c)})
                return

    take("easy", easy, lambda c: {"solve_rate": rate(c), "players": st(c).players})
    pop = [(c, "rating") for c in rated] + [(c, "recent") for c in recent]
    for c, kind in pop:
        if c["id"] not in used:
            used.add(c["id"])
            out.append({"case_id": c["id"], "reason": "popular",
                        **({"rating_avg": ratings[c["id"]][0], "rating_count": ratings[c["id"]][1]} if kind == "rating"
                           else {"solved_30d": st(c).recent})})
            break
    take("taste", taste, lambda c: {"category": c["category"], "category_solved": solved_categories.get(c["category"], 0)})
    return out[:MAX_PICKS]


async def picks_for(session: AsyncSession, player_id: str, candidates: list[dict], category_of: dict[str, str],
                    ratings: dict[str, tuple[float, int, int]]) -> list[dict]:
    """`candidates` are the archive cases before removing this player's solved/lost ones."""
    mine = (await session.execute(select(CaseProgress.case_id, CaseProgress.solved, CaseProgress.failed)
                                  .where(CaseProgress.player_id == player_id))).all()
    done = {cid for cid, solved, failed in mine if solved or failed}
    cats: dict[str, int] = {}
    for cid, solved, _ in mine:
        if solved and category_of.get(cid):
            cats[category_of[cid]] = cats.get(category_of[cid], 0) + 1
    left = [c for c in candidates if c["id"] not in done]
    if not left:
        return []
    return choose(left, cats, await case_stats(session), ratings)
