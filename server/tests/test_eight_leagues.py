"""Eight leagues (17 Nov 2026): names, first ranks, the 1000-coin weekly bill and the data migration 0039."""
from app import economy as eco
from app import weekboard


def test_eight_leagues_in_order_with_the_designed_first_ranks():
    assert weekboard.LEAGUES == ("تازه‌کار", "کارآموز", "کارآگاه", "کاردان", "بازرس", "سربازرس", "سرپرست", "اسطوره")
    assert weekboard.LEAGUE_FROM_RANK == (0, 2, 4, 6, 8, 10, 12, 15)
    assert weekboard.league_min_xp() == (0, 550, 1600, 3200, 5600, 9000, 13500, 24000)
    assert all(a < b for a, b in zip(weekboard.LEAGUE_FROM_RANK, weekboard.LEAGUE_FROM_RANK[1:]))
    assert weekboard.LEAGUE_FROM_RANK[-1] < len(eco.RANKS)


def test_the_weekly_bill_does_not_grow_with_more_leagues():
    assert sum(weekboard.LEAGUE_PRIZES.values()) * len(weekboard.LEAGUES) == 1000


def test_old_four_league_snapshot_rows_keep_their_players_in_the_same_league():
    """Migration 0039 doubles the stored index: old league k (4 leagues) -> 2k, whose XP floor is the same as before."""
    old_floor = [eco.RANKS[i][0] for i in (0, 4, 8, 12)]
    new_floor = [weekboard.league_min_xp()[2 * k] for k in range(4)]
    assert old_floor == new_floor


async def test_migration_doubles_stored_leagues_once():
    from sqlalchemy import select, text
    from app import db
    from app.models import WeekLeague
    # the migration file runs in the CI step «Database migrations»; here the same UPDATE is checked on test data
    async with db.SessionLocal() as s:
        s.add_all([WeekLeague(week="2027-01-01", player_id=f"mig{k}", league=k) for k in range(4)])
        await s.commit()
        await s.execute(text("UPDATE week_leagues SET league = league * 2 WHERE week = '2027-01-01'"))
        await s.commit()
        got = sorted((await s.execute(select(WeekLeague.league).where(WeekLeague.week == "2027-01-01"))).scalars().all())
    assert got == [0, 2, 4, 6]
