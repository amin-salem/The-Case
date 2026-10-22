"""Anti-cheat rules (see docs/operations.md). Every case has one answer, so the threats are a throwaway account
that fails a case and reads the answer for the main account, and many accounts farming coins.

- delayed answers: a lost case shows its culprit/proof/explanation only when the case is closed
- proof of investigation: 3 stars and a leaderboard place need active time and interrogated suspects
- throwaway accounts: hidden from the leaderboards for 48 h unless secured with an email; invitations are paid late
- a per-player shuffle of suspects and evidence, so "pick the third one" is useless
"""
from __future__ import annotations

import hashlib
import logging
import re
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.exc import IntegrityError

from . import content, gameclock
from . import economy as eco
from .models import CaseProgress, InboxItem, Player, ReferralPayout, utcnow

log = logging.getLogger("anticheat")


def now_utc() -> datetime:
    """Now as naive UTC, read from the game clock (the same clock the cases use, so tests can move it)."""
    return content.now_local().astimezone(timezone.utc).replace(tzinfo=None)


# ---------------------------------------------------------------- delayed answers
def reveal_time(c: content.Case, failed_at: datetime) -> datetime | None:
    """When the answer of a case that was just lost becomes public (naive UTC); None = at once.
    Nightly case: the next case opening. Weekend case: its closing. Story chapter: 24 hours after the failure.
    Archive cases (already past their day): at once."""
    if content.is_story(c.id):
        return failed_at + timedelta(hours=eco.STORY_ANSWER_DELAY_HOURS)
    if content.is_weekly(c.id):
        at = content.weekly_closes_at(c)
    else:
        today = content.todays_case()
        if today is None or today.id != c.id:
            return None
        at = content.next_case_at()
    at = at.astimezone(timezone.utc).replace(tzinfo=None)
    return at if at > failed_at else None


def answer_visible(p: CaseProgress | None) -> bool:
    """May this player see the culprit, the proof and the explanation of the case?"""
    if p is None:
        return False
    if p.solved:
        return True
    if not p.failed:
        return False
    return p.reveal_at is None or p.reveal_at <= now_utc()


def answer_pending(p: CaseProgress | None) -> bool:
    return bool(p and p.failed and not p.solved and not answer_visible(p))


def answer_at_ts(p: CaseProgress | None) -> int | None:
    """Unix time when a hidden answer becomes public (None when it is public or the case is not lost)."""
    if answer_pending(p):
        return int(p.reveal_at.replace(tzinfo=timezone.utc).timestamp())
    return None


# ---------------------------------------------------------------- proof of investigation
def proof_ok(p: CaseProgress, c: content.Case) -> bool:
    """Enough real work on the case for 3 stars and a leaderboard place? The needed time follows the case's difficulty
    (eco.min_active_seconds): a quick reader who reaches the clue on an easy case is not punished as a cheater."""
    need = eco.min_active_seconds(c.data.get("difficulty"))
    return (p.active_seconds or 0) >= need and len(p.seen or []) >= eco.MIN_SUSPECTS_SEEN


# ---------------------------------------------------------------- investigation depth
_ASK = re.compile(r"^[A-Za-z0-9_-]{1,16}:\d{1,2}$")
DEPTH_CAP = 80


def merge_depth(p: CaseProgress, c: content.Case, cards: list[str] | None, asks: list[str] | None) -> None:
    """Adds what the app reports (evidence cards opened, "suspect:question" keys asked) to the progress row. Only ids
    that exist in THIS case are kept, each list is a set bounded to DEPTH_CAP entries, so garbage cannot inflate it.
    None for both = an old app: the columns stay None (= "never reported")."""
    if cards is None and asks is None:
        return
    ev = {e["id"] for e in c.data.get("evidence", [])}
    sus = {s["id"] for s in c.data.get("suspects", [])}
    have_c = set(p.cards_opened or [])
    have_q = set(p.questions_asked or [])
    for x in cards or []:
        if x in ev and len(have_c) < DEPTH_CAP:
            have_c.add(x)
    for x in asks or []:
        if _ASK.match(x) and x.split(":", 1)[0] in sus and len(have_q) < DEPTH_CAP:
            have_q.add(x)
    p.cards_opened, p.questions_asked = sorted(have_c), sorted(have_q)


def depth_summary(p: CaseProgress, c: content.Case) -> dict:
    cards = set(p.cards_opened or [])
    return {"evidence": len(cards), "questions": len(set(p.questions_asked or [])),
            "proof_opened": bool(cards & set(c.proof)), "active": int(p.active_seconds or 0)}


def depth_ok(p: CaseProgress, c: content.Case) -> tuple[bool, str]:
    """Is the investigation deep enough for a leaderboard place? (ok, reason). Plain nightly and archive cases only
    (weekend and story cases have their own formats). Never blocks solving; stars and coins do not depend on it."""
    from .config import get_settings
    st = get_settings()
    if not st.depth_gate_enabled or content.is_weekly(c.id) or content.is_story(c.id):
        return True, ""
    if p.cards_opened is None and p.questions_asked is None:
        return (not st.depth_require_report), ("no_report" if st.depth_require_report else "")
    d = depth_summary(p, c)
    need_cards = min(st.depth_min_cards, len(c.data.get("evidence", [])))
    if d["evidence"] < need_cards:
        return False, "cards"
    if d["questions"] < st.depth_min_questions:
        return False, "questions"
    if st.depth_need_proof and not d["proof_opened"]:
        return False, "proof"
    return True, ""


# ---------------------------------------------------------------- throwaway accounts
def visible_player():
    """SQL condition: players who may appear on the leaderboards and win weekly prizes. Banned players and accounts
    younger than 48 hours that are not secured with an email are hidden (they still play)."""
    cutoff = utcnow() - timedelta(hours=eco.HIDE_NEW_ACCOUNT_HOURS)
    return and_(Player.banned.is_(False), Player.tester.is_(False), or_(Player.email.is_not(None), Player.phone_hash.is_not(None), Player.created_at <= cutoff))


def is_visible(pl: Player) -> bool:
    if pl.banned or pl.tester:
        return False
    return bool(pl.email or pl.phone_hash) or pl.created_at <= utcnow() - timedelta(hours=eco.HIDE_NEW_ACCOUNT_HOURS)


async def maybe_pay_referral(player_id: str) -> bool:
    """Called after a solve. The inviter is paid once the invited player solved cases on INVITE_MIN_DAYS different
    days; at most INVITE_PAID_PER_WEEK paid invites per inviter per week and 1 per device. Atomic: the flag update,
    the unique rows of ReferralPayout and the single commit make a double payment impossible. It uses its own
    session, so a refusal can never undo the solve. Returns True if the inviter was paid."""
    from . import db

    async with db.SessionLocal() as session:
        await db.begin_write(session)
        player = await session.get(Player, player_id)
        if player is None or not player.referred_by:
            return False
        inviter_id = player.referred_by
        locked = await db.lock_players(session, [player_id, inviter_id])
        player = locked.get(player_id)
        if player is None or not player.referred_by or player.referral_paid:
            return False
        days = int(await session.scalar(select(func.count(func.distinct(CaseProgress.day))).where(
            CaseProgress.player_id == player.id, CaseProgress.solved.is_(True), CaseProgress.day != "")) or 0)
        if days < eco.INVITE_MIN_DAYS:
            return False
        claim = await session.execute(update(Player).where(Player.id == player.id, Player.referral_paid.is_(False))
                                      .values(referral_paid=True))
        if claim.rowcount != 1:  # another request paid (or refused) it at the same moment
            await session.rollback()
            return False
        inviter = locked.get(inviter_id)
        week = gameclock.week_of(content.now_local()).isoformat()
        if inviter is None or inviter.banned or inviter.invites_rewarded >= eco.MAX_REWARDED_INVITES:
            await session.commit()
            log.info("referral refused reason=inviter_unavailable")
            return False
        used = int(await session.scalar(select(func.count()).select_from(ReferralPayout).where(
            ReferralPayout.inviter_id == inviter.id, ReferralPayout.week == week)) or 0)
        if used >= eco.INVITE_PAID_PER_WEEK:
            await session.commit()
            log.info("referral refused reason=weekly_cap")
            return False
        session.add(ReferralPayout(inviter_id=inviter.id, invitee_id=player.id, device_id=player.device_id,
                                   week=week, slot=used + 1))
        inviter.invites_rewarded += 1
        session.add(InboxItem(player_id=inviter.id, title="یه کارآگاه تازه با کد تو اومد!",
                              message=f"{player.nickname} چند روز پرونده حل کرد؛ جایزه‌ی دعوتت آماده‌ست.",
                              grants=[{"type": "coins", "amount": eco.INVITE_INVITER}], source="referral"))
        try:
            await session.commit()
        except IntegrityError:  # this device already paid out once, or a parallel request took the slot
            await session.rollback()
            await session.execute(update(Player).where(Player.id == player_id).values(referral_paid=True))
            await session.commit()
            log.info("referral refused reason=device_or_slot")
            return False
        log.info("referral paid slot=%d", used + 1)
        return True


# ---------------------------------------------------------------- per-player shuffle
def shuffled(items: list, seed: str) -> list:
    """The same list in an order that depends on the seed (player id + case id) and only on each item's id,
    so the order stays stable when items are added later (weekend evidence). Ids are unchanged."""
    def key(x):
        ident = x.get("id", "") if isinstance(x, dict) else str(x)
        return hashlib.sha256(f"{seed}:{ident}".encode()).hexdigest()

    return sorted(items, key=key)
