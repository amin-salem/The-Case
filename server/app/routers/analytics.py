"""One aggregate-only report; its expiring key grants no admin or player access."""
from typing import Literal

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ..cache import TTLCache
from ..db import get_session
from ..security import require_analytics
from ..services import funnel

router = APIRouter(prefix="/v1/analytics", tags=["analytics"], dependencies=[Depends(require_analytics)])
_cache = TTLCache("analytics_funnel", ttl=60, max_size=4)


# Explicit response fields: a later internal report change cannot silently expose
# player records, payment tokens or arbitrary text to this restricted credential.
# BaseModel's default extra='ignore' also applies to every nested model below.
class SectionError(BaseModel):
    error: Literal["section_failed"]


class SignupDay(BaseModel):
    day: str
    new: int


class Signups(BaseModel):
    days: list[SignupDay]
    total: int


class FunnelCounts(BaseModel):
    registered: int
    opened: int
    finished_first: int
    solved_first: int
    solved_3_days: int


class FunnelDay(FunnelCounts):
    day: str


class FunnelPercentages(BaseModel):
    registered: float | None
    opened: float | None
    finished_first: float | None
    solved_first: float | None
    solved_3_days: float | None


class Funnel(BaseModel):
    days: list[FunnelDay]
    total: FunnelCounts
    pct: FunnelPercentages


class RetentionDay(SignupDay):
    d1: int | None
    d3: int | None
    d7: int | None


class Cohort(BaseModel):
    returned: int
    of: int
    pct: float | None
    cohorts: int


class RetentionTotals(BaseModel):
    d1: Cohort
    d3: Cohort
    d7: Cohort


class Active(BaseModel):
    players: int
    dau: int
    wau: int
    dau_pct: float | None
    wau_pct: float | None
    dau_wau_pct: float | None


class Retention(BaseModel):
    days: list[RetentionDay]
    total: RetentionTotals
    active: Active


class DropStage(BaseModel):
    key: str
    label: str
    players: int
    pct: float | None


class AbandonedCase(BaseModel):
    case: str
    title: str
    abandoned: int


class DropOff(BaseModel):
    stopped_after_hours: int
    stopped: int
    stages: list[DropStage]
    abandoned_cases: list[AbandonedCase]


class Pack(BaseModel):
    product: str
    granted: int
    refunded: int
    rejected: int
    coins: int | None
    vip_days: int | None
    no_ads: bool


class Balances(BaseModel):
    active_players: int
    p25: float | None
    median: float | None
    p75: float | None
    zero_pct: float | None


class Money(BaseModel):
    registered: int
    payers: int
    conversion_pct: float | None
    d7_retained: int
    d7_retained_payers: int
    d7_conversion_pct: float | None
    first_purchase_median_hours: float | None
    packs: list[Pack]
    coins: Balances


class Plaques(BaseModel):
    # These keys are numeric strings in the existing report.
    model_config = {"populate_by_name": True}
    three: int = Field(alias="3")
    two: int = Field(alias="2")
    one: int = Field(alias="1")
    three_pct: float | None = Field(alias="3_pct")
    two_pct: float | None = Field(alias="2_pct")
    one_pct: float | None = Field(alias="1_pct")


class CaseQuality(BaseModel):
    case: str
    title: str
    opened: int
    solved: int
    failed: int
    solved_pct: float | None
    failed_pct: float | None
    median_active_seconds: int | None


class Quality(BaseModel):
    opened: int
    finished: int
    solved: int
    failed: int
    failed_pct: float | None
    plaques: Plaques
    median_active_seconds: int | None
    avg_hints: float | None
    cases_days: int
    cases: list[CaseQuality]


class Report(BaseModel):
    days: int
    generated_at: int
    timezone: str
    first_day: str
    last_day: str
    signups: Signups | SectionError
    funnel: Funnel | SectionError
    retention: Retention | SectionError
    drop_off: DropOff | SectionError
    money: Money | SectionError
    quality: Quality | SectionError


def aggregate_only(raw: dict) -> dict:
    safe = Report.model_validate(raw).model_dump(by_alias=True)
    # Never forward an arbitrary internal text field: derive it from safe fields.
    safe["text"] = funnel.summary_text(safe)
    return safe


@router.get("/funnel", include_in_schema=False)
async def report(days: int = Query(30, ge=1, le=90), session: AsyncSession = Depends(get_session)):
    async def load():
        return aggregate_only(await funnel.build(session, days))

    # Authentication runs on EVERY request, including cache hits and after expiry.
    data = await _cache.get_or_load(days, load)
    return JSONResponse(data, headers={"Cache-Control": "no-store", "Vary": "X-Analytics-Key"})
