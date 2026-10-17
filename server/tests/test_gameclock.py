"""The one game clock (app/gameclock.py): game day 21:00-21:00 Tehran, week Friday 21:00 - Friday 21:00."""
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from app import content, gameclock

from .conftest import new_player
from .test_anticheat import accuse

TEHRAN = ZoneInfo("Asia/Tehran")


def T(y, m, d, h=0, mi=0, s=0):
    return datetime(y, m, d, h, mi, s, tzinfo=TEHRAN)


def test_game_day_changes_at_21_not_at_midnight():
    assert gameclock.game_day(T(2026, 10, 17, 20, 59)) == date(2026, 10, 16)
    assert gameclock.game_day(T(2026, 10, 17, 21, 1)) == date(2026, 10, 17)
    assert gameclock.game_day(T(2026, 10, 18, 0, 30)) == date(2026, 10, 17)   # after midnight: still the same game day
    assert gameclock.game_day(T(2026, 10, 18, 20, 59, 59)) == date(2026, 10, 17)
    assert gameclock.game_day(T(2026, 10, 18, 21, 0, 0)) == date(2026, 10, 18)


def test_calendar_day_is_still_midnight():
    assert gameclock.calendar_day(T(2026, 10, 17, 23, 59)) == date(2026, 10, 17)
    assert gameclock.calendar_day(T(2026, 10, 18, 0, 1)) == date(2026, 10, 18)


def test_utc_input_is_converted_to_tehran():
    # 17:29 UTC = 20:59 Tehran; 17:31 UTC = 21:01 Tehran
    assert gameclock.game_day(datetime(2026, 10, 17, 17, 29, tzinfo=timezone.utc)) == date(2026, 10, 16)
    assert gameclock.game_day(datetime(2026, 10, 17, 17, 31, tzinfo=timezone.utc)) == date(2026, 10, 17)
    assert gameclock.game_day(datetime(2026, 10, 17, 17, 31)) == date(2026, 10, 17)  # naive = UTC like the database


def test_next_rollover_is_21_00():
    assert gameclock.next_rollover(T(2026, 10, 17, 20, 59)) == T(2026, 10, 17, 21)
    assert gameclock.next_rollover(T(2026, 10, 17, 21, 1)) == T(2026, 10, 18, 21)
    assert gameclock.next_rollover(T(2026, 10, 18, 3)) == T(2026, 10, 18, 21)


def test_week_runs_friday_21_to_friday_21():
    fri = date(2026, 10, 16)
    assert fri.weekday() == 4
    assert gameclock.week_of(T(2026, 10, 16, 20, 59)) == date(2026, 10, 9)    # Friday evening before the release: old week
    assert gameclock.week_of(T(2026, 10, 16, 21, 0)) == fri                    # the Friday case opens the NEW week
    assert gameclock.week_of(T(2026, 10, 17, 12)) == fri                        # Saturday
    assert gameclock.week_of(T(2026, 10, 22, 23)) == fri                        # Thursday night is the last day
    assert gameclock.week_of(T(2026, 10, 23, 20, 59)) == fri
    assert gameclock.week_of(T(2026, 10, 23, 21, 0)) == date(2026, 10, 23)
    assert gameclock.week_begin(fri) == T(2026, 10, 16, 21)
    assert gameclock.week_end(fri) == T(2026, 10, 23, 21)
    assert gameclock.week_end(fri) - gameclock.week_begin(fri) == timedelta(days=7)
    assert gameclock.settle_at(fri) == T(2026, 10, 23, 21, 10)


def test_a_week_is_exactly_seven_game_days():
    ws = date(2026, 10, 16)
    days = {gameclock.game_day(gameclock.week_begin(ws) + timedelta(hours=h)) for h in range(0, 24 * 7, 5)}
    assert days == {ws + timedelta(days=i) for i in range(7)}
    assert {gameclock.week_start(d) for d in days} == {ws}


def test_month_and_year_boundaries():
    assert gameclock.game_day(T(2026, 12, 31, 22)) == date(2026, 12, 31)
    assert gameclock.game_day(T(2027, 1, 1, 1)) == date(2026, 12, 31)
    assert gameclock.game_day(T(2027, 1, 1, 21, 1)) == date(2027, 1, 1)
    assert gameclock.week_of(T(2027, 1, 1, 1)) == date(2026, 12, 25)   # Friday 25 Dec 21:00 - Friday 1 Jan 21:00
    assert gameclock.week_of(T(2027, 1, 1, 21, 1)) == date(2027, 1, 1)
    assert gameclock.game_day(T(2026, 10, 31, 23)) == date(2026, 10, 31)
    assert gameclock.game_day(T(2026, 11, 1, 20, 59)) == date(2026, 10, 31)


def test_case_belongs_to_the_week_it_was_published_in():
    c = content.by_id("c018")           # published Friday 16 Oct 2026, opens 21:00: first case of the week
    assert c.publish == date(2026, 10, 16) and content.case_week(c) == date(2026, 10, 16)
    last = next(x for x in content.all_cases() if x.publish == date(2026, 10, 22))   # Thursday: last case of that week
    assert content.case_week(last) == date(2026, 10, 16)
    nxt = next(x for x in content.all_cases() if x.publish == date(2026, 10, 23))
    assert content.case_week(nxt) == date(2026, 10, 23)
    ids = [x.publish for x in content.week_cases(date(2026, 10, 16)) if not content.is_weekly(x.id)]
    assert ids == [date(2026, 10, 16) + timedelta(days=i) for i in range(7)]   # 7 daily cases


def test_every_daily_case_has_a_full_24_hours():
    for c in content.all_cases():
        assert content.next_case_at(content.opens_at(c)) - content.opens_at(c) == timedelta(hours=24)


def test_mission_day_labels_are_unchanged():
    # missions: named by the NEXT date from 21:00, same as before the game clock existed
    assert content.mission_day_str(T(2026, 10, 17, 20, 59)) == "2026-10-17"
    assert content.mission_day_str(T(2026, 10, 17, 21, 1)) == "2026-10-18"
    assert content.mission_day_str(T(2026, 10, 18, 2)) == "2026-10-18"
    assert content.mission_next_at(T(2026, 10, 17, 22)) == T(2026, 10, 18, 21)


def test_injectable_clock():
    gameclock.set_clock(lambda: T(2026, 10, 17, 22))
    try:
        assert gameclock.now() == T(2026, 10, 17, 22) and gameclock.game_day() == date(2026, 10, 17)
    finally:
        gameclock.set_clock(None)


async def test_streak_survives_the_rollover(client, monkeypatch):
    """A streak follows the cases, not the calendar: solving the old case at 20:59 and the new one at 21:01 is 2 in a row."""
    a, b = content.by_id("c030"), content.by_id("c031")
    p = await new_player(client, "clock-streak")
    h = p["headers"]
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(a) + timedelta(hours=2))
    await client.get(f"/v1/cases/{a.id}", headers=h)
    assert (await accuse(client, h, a, a.culprit))["streak"] == 1
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(b) - timedelta(minutes=1))   # 20:59, still case a
    assert content.todays_case().id == a.id
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(b) + timedelta(minutes=1))   # 21:01, case b
    assert content.todays_case().id == b.id
    await client.get(f"/v1/cases/{b.id}", headers=h)
    assert (await accuse(client, h, b, b.culprit))["streak"] == 2
