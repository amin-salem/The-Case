"""Case comments: a detective who finished a case may leave 1-5 stars and a comment, and reply to approved comments.
Nothing is public until the admin approves it (the admin panel's «نظرها» tab). One comment per player per case."""
import re

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from ..config import get_settings
from ..db import get_session
from ..models import AdminLog, CaseComment, CaseProgress, Player, new_id, utcnow
from ..security import current_player, require_admin
from ..util import ts

router = APIRouter(prefix="/v1/cases", tags=["comments"])
admin_router = APIRouter(prefix="/admin/api/comments", tags=["admin"], dependencies=[Depends(require_admin)])

MAX_ROOT, MAX_REPLY = 300, 200
PAGE = 20
MAX_REPLIES_PER_CASE = 20      # replies one player may write under one case
MAX_OPEN_REPLIES = 5           # ... of which at most this many may wait for approval
_LINK = re.compile(r"(https?:|www\.|t\.me|@\w|\.(com|ir|net|org|me|io)\b)", re.I)


def _on() -> None:
    if not get_settings().comments_enabled:
        raise HTTPException(503, "comments_off")


def _known_case(case_id: str) -> None:
    if not (content.by_id(case_id) or content.weekly_by_id(case_id) or content.story_by_id(case_id)):
        raise HTTPException(404, "no_case")


def _clean(text: str, lo: int, hi: int) -> str:
    t = " ".join((text or "").split())
    if len(t) < lo:
        raise HTTPException(422, "comment_too_short")
    if len(t) > hi:
        raise HTTPException(422, "comment_too_long")
    if _LINK.search(t):
        raise HTTPException(422, "no_links")
    return t


class CommentIn(BaseModel):
    body: str = Field(max_length=2000)
    rating: int = Field(0, ge=0, le=5)
    parent_id: int | None = None


def _item(c: CaseComment, nick: dict, mine: str) -> dict:
    n = nick.get(c.player_id) or ("", 0)
    return {"id": c.id, "nickname": n[0] or "کارآگاه", "avatar": n[1], "rating": c.rating, "body": c.body,
            "created_at": ts(c.created_at), "status": c.status, "mine": c.player_id == mine, "replies": []}


@router.get("/{case_id}/comments")
async def list_comments(case_id: str, before: int = Query(0, ge=0), player: Player = Depends(current_player),
                        session: AsyncSession = Depends(get_session)):
    _on()
    _known_case(case_id)
    C = CaseComment
    agg = (await session.execute(select(func.count(), func.coalesce(func.avg(C.rating), 0)).where(
        C.case_id == case_id, C.parent_id.is_(None), C.status == "approved"))).one()
    q = select(C).where(C.case_id == case_id, C.parent_id.is_(None), C.status == "approved")
    if before:
        q = q.where(C.id < before)
    roots = (await session.execute(q.order_by(C.id.desc()).limit(PAGE + 1))).scalars().all()
    more = len(roots) > PAGE
    roots = roots[:PAGE]
    ids = [r.id for r in roots]
    replies = []
    if ids:
        replies = (await session.execute(select(C).where(
            C.parent_id.in_(ids), (C.status == "approved") | ((C.player_id == player.id) & (C.status == "pending")))
            .order_by(C.id).limit(400))).scalars().all()
    mine = (await session.execute(select(C).where(
        C.case_id == case_id, C.player_id == player.id, C.slot == "root"))).scalar_one_or_none()
    pids = {r.player_id for r in roots} | {r.player_id for r in replies} | ({player.id} if mine else set())
    nick = {pid: (n, a) for pid, n, a in (await session.execute(
        select(Player.id, Player.nickname, Player.avatar).where(Player.id.in_(pids)))).all()} if pids else {}
    by_id = {r.id: _item(r, nick, player.id) for r in roots}
    for r in replies:
        if r.parent_id in by_id:
            by_id[r.parent_id]["replies"].append(_item(r, nick, player.id))
    done = (await session.execute(select(CaseProgress.id).where(
        CaseProgress.player_id == player.id, CaseProgress.case_id == case_id,
        CaseProgress.finished_at.is_not(None)))).first() is not None
    return {"count": int(agg[0]), "average": round(float(agg[1]), 1), "items": [by_id[i] for i in ids],
            "more": more, "can_write": done,
            "mine": _item(mine, nick, player.id) if mine is not None and mine.status != "approved" else None,
            "has_mine": mine is not None}


@router.post("/{case_id}/comments")
async def write_comment(case_id: str, body: CommentIn, player: Player = Depends(current_player),
                        session: AsyncSession = Depends(get_session)):
    _on()
    _known_case(case_id)
    C = CaseComment
    done = (await session.execute(select(CaseProgress.id).where(
        CaseProgress.player_id == player.id, CaseProgress.case_id == case_id,
        CaseProgress.finished_at.is_not(None)))).first()
    if done is None:
        raise HTTPException(409, "finish_case_first")
    if body.parent_id is None:
        if not 1 <= body.rating <= 5:
            raise HTTPException(422, "rating_needed")
        text = _clean(body.body, 3, MAX_ROOT)
        old = (await session.execute(select(C).where(
            C.case_id == case_id, C.player_id == player.id, C.slot == "root"))).scalar_one_or_none()
        if old is not None:
            if old.status != "rejected":
                raise HTTPException(409, "already_commented")
            old.rating, old.body, old.status, old.reviewed_at, old.created_at = body.rating, text, "pending", None, utcnow()
            row = old
        else:
            row = C(case_id=case_id, player_id=player.id, slot="root", rating=body.rating, body=text)
            session.add(row)
    else:
        text = _clean(body.body, 2, MAX_REPLY)
        parent = await session.get(C, body.parent_id)
        if parent is None or parent.case_id != case_id or parent.parent_id is not None or parent.status != "approved":
            raise HTTPException(404, "no_comment")
        mine = (await session.execute(select(C.status).where(
            C.case_id == case_id, C.player_id == player.id, C.parent_id.is_not(None)))).scalars().all()
        if len(mine) >= MAX_REPLIES_PER_CASE or sum(1 for s in mine if s == "pending") >= MAX_OPEN_REPLIES:
            raise HTTPException(429, "too_many_replies")
        row = C(case_id=case_id, player_id=player.id, parent_id=parent.id, slot=new_id(), rating=0, body=text)
        session.add(row)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "already_commented")
    return {"id": row.id, "status": row.status}


# ---------------------------------------------------------------- admin
async def _case_title(case_id: str) -> str:
    c = content.by_id(case_id) or content.weekly_by_id(case_id) or content.story_by_id(case_id)
    t = (c.data.get("title") if c and isinstance(c.data, dict) else None) or ""
    return t


@admin_router.get("")
async def admin_list(status: str = Query("pending", pattern="^(pending|approved|rejected|hidden)$"),
                     case_id: str = Query("", max_length=16), before: int = Query(0, ge=0),
                     limit: int = Query(30, ge=1, le=100), session: AsyncSession = Depends(get_session)):
    C = CaseComment
    q = select(C).where(C.status == status)
    if case_id:
        q = q.where(C.case_id == case_id)
    if before:
        q = q.where(C.id < before)
    rows = (await session.execute(q.order_by(C.id.desc()).limit(limit + 1))).scalars().all()
    more = len(rows) > limit
    rows = rows[:limit]
    pids = {r.player_id for r in rows}
    nick = {pid: n for pid, n in (await session.execute(
        select(Player.id, Player.nickname).where(Player.id.in_(pids)))).all()} if pids else {}
    parents = {}
    pid_ids = {r.parent_id for r in rows if r.parent_id}
    if pid_ids:
        parents = {p.id: p.body for p in (await session.execute(select(C).where(C.id.in_(pid_ids)))).scalars().all()}
    return {"more": more, "items": [{
        "id": r.id, "case_id": r.case_id, "case_title": await _case_title(r.case_id), "player_id": r.player_id,
        "nickname": nick.get(r.player_id) or "", "rating": r.rating, "body": r.body, "status": r.status,
        "reply_to": parents.get(r.parent_id, "") if r.parent_id else "", "created_at": ts(r.created_at)} for r in rows]}


@admin_router.get("/cases")
async def admin_cases(session: AsyncSession = Depends(get_session)):
    C = CaseComment
    rows = (await session.execute(select(
        C.case_id, C.status, func.count(), func.coalesce(func.avg(func.nullif(C.rating, 0)), 0))
        .group_by(C.case_id, C.status))).all()
    out: dict[str, dict] = {}
    for case_id, st, n, avg in rows:
        d = out.setdefault(case_id, {"case_id": case_id, "pending": 0, "approved": 0, "average": 0.0})
        if st == "pending":
            d["pending"] += int(n)
        elif st == "approved":
            d["approved"] += int(n)
            d["average"] = round(float(avg), 1)
    res = []
    for d in out.values():
        d["title"] = await _case_title(d["case_id"])
        res.append(d)
    res.sort(key=lambda d: (-d["pending"], d["case_id"]))
    return {"items": res, "pending": sum(d["pending"] for d in res)}


class ActionIn(BaseModel):
    action: str = Field(pattern="^(approve|reject|hide|delete)$")


@admin_router.post("/{comment_id}")
async def admin_action(comment_id: int, body: ActionIn, session: AsyncSession = Depends(get_session)):
    c = await session.get(CaseComment, comment_id)
    if c is None:
        raise HTTPException(404, "no_comment")
    if body.action == "delete":
        await session.execute(delete(CaseComment).where(CaseComment.parent_id == c.id))
        await session.delete(c)
        status = "deleted"
    else:
        status = {"approve": "approved", "reject": "rejected", "hide": "hidden"}[body.action]
        c.status, c.reviewed_at = status, utcnow()
    session.add(AdminLog(action=f"comment_{body.action}", target=str(comment_id), detail={"case": c.case_id}))
    await session.commit()
    return {"id": comment_id, "status": status}
