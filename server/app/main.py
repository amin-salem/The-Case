"""«پرونده» game server.

Run locally:   uvicorn app.main:app --reload
API docs:      http://127.0.0.1:8000/docs
"""
import logging
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import cheatreport, content, db, gameclock, rewards, riddles, weekboard
from .config import get_settings
from .version import VERSION

log = logging.getLogger("main")
from .routers import admin, admin_ui, analytics, avatars as avatar_routes, auth, cases, comments, inbox, leaderboard, meta, pages, phone, profile, purchases
from .routers import tools as tool_routes
from .routers import achievements as achievement_routes
from .routers import missions as mission_routes
from .routers import riddles as riddle_routes
from .routers import story as story_routes
from .services import ratelimit, runtime_stats
from .services.ratelimit import RateLimitMiddleware, RateLimited


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    s.check_production()
    content.all_cases()  # fail fast if a case file is broken
    riddles.all_riddles()
    content.weekly_cases()
    if s.auto_create_tables:
        await db.create_tables()
    async def weekly_prizes():
        while True:
            try:
                async with db.SessionLocal() as ses:
                    if weekboard.leagues_on():  # the league snapshot of a new week is taken at its start, once
                        await weekboard.ensure_snapshot(ses, gameclock.week_of(content.now_local()))
                    await rewards.settle_last_week(ses)
                    await cheatreport.store_weekly(ses)
            except Exception:
                log.exception("weekly job failed")
            await asyncio.sleep(300)

    task = asyncio.create_task(weekly_prizes())
    rl_task = asyncio.create_task(ratelimit.cleanup_loop())
    meter_task = asyncio.create_task(runtime_stats.sampler())
    yield
    task.cancel()
    rl_task.cancel()
    meter_task.cancel()
    await db.engine.dispose()


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(title="The Case API", version=VERSION, lifespan=lifespan,
                  docs_url="/docs" if s.env != "prod" else None, redoc_url=None)
    app.add_middleware(RateLimitMiddleware)
    app.add_exception_handler(RateLimited, lambda request, exc: ratelimit.rate_limited_response(exc))
    app.add_middleware(CORSMiddleware, allow_origins=[o.strip() for o in s.cors_origins.split(",")],
                       allow_methods=["*"], allow_headers=["*"])
    app.add_middleware(runtime_stats.StatsMiddleware)  # outermost: counts every request and 5xx
    for r in (analytics.router, meta.router, pages.router, auth.router, phone.router, profile.router, cases.router, leaderboard.router,
              purchases.router, riddle_routes.router, mission_routes.router, achievement_routes.router, avatar_routes.router, story_routes.router, tool_routes.router, comments.router, comments.admin_router, inbox.router, admin.router, admin_ui.page_router, admin_ui.router):
        app.include_router(r)
    return app


app = create_app()

