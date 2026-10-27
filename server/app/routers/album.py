"""GET /v1/album: the culprit album (app/album.py). One read, built from the player's CaseProgress rows."""
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import album, avatars, content, progress
from ..db import get_session
from ..models import CaseProgress, Player
from ..security import current_player
from .cases import _can_open, _unlock_cost

router = APIRouter(prefix="/v1/album", tags=["album"])


@router.get("")
async def get_album(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    cases = await album.skeleton()
    rows = {p.case_id: p for p in (await session.execute(
        select(CaseProgress).where(CaseProgress.player_id == player.id))).scalars().all()}
    solved = {cid for cid, p in rows.items() if p.solved}
    today = content.todays_case()
    entries, groups = [], {}
    for c in cases:
        p = rows.get(c.id)
        openable = bool(p and p.solved) or _can_open(c, p, player, today)
        entries.append(album.entry(c, p, openable=openable, price=0 if openable else _unlock_cost(c, p)))
        key, name, icon = album.group_of(c.data)
        g = groups.setdefault(key, {"key": key, "title": name, "icon": icon, "total": 0, "solved": 0})
        g["total"] += 1
        g["solved"] += c.id in solved
    for g in groups.values():
        g["complete"] = g["total"] >= album.GROUP_MIN and g["solved"] == g["total"]
    done = sum(1 for g in groups.values() if g["complete"])
    # a player who completed groups before this feature (or whose stat is behind) is rewarded now: insert-or-ignore
    new = []
    if done > int((player.stats or {}).get("album_groups", 0)):
        progress.set_stat_max(player, "album_groups", done)
        gains = progress.Gains()
        await avatars.check_goals(session, player, gains)
        await session.commit()
        new = gains.avatars
    owned = await avatars.owned_rows(session, player)
    rewards = [{"id": i.id, "title": i.title, "need": i.target, "owned": ("frame", i.id) in owned}
               for i in avatars.FRAMES if i.metric == "album_groups"]
    return JSONResponse({"cards": entries, "groups": list(groups.values()), "groups_done": done, "rewards": rewards,
                           "new": new, "solved": len(solved), "total": len(cases)})
