"""«پرونده» game server.

Run locally:   uvicorn app.main:app --reload
API docs:      http://127.0.0.1:8000/docs
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import content, db, riddles
from .config import get_settings
from .version import VERSION
from .routers import admin, auth, cases, inbox, leaderboard, meta, pages, profile, purchases
from .routers import riddles as riddle_routes
from .services.ratelimit import RateLimitMiddleware


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    s.check_production()
    content.all_cases()  # fail fast if a case file is broken
    riddles.all_riddles()
    if s.auto_create_tables:
        await db.create_tables()
    yield
    await db.engine.dispose()


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(title="The Case API", version=VERSION, lifespan=lifespan,
                  docs_url="/docs" if s.env != "prod" else None, redoc_url=None)
    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(CORSMiddleware, allow_origins=[o.strip() for o in s.cors_origins.split(",")],
                       allow_methods=["*"], allow_headers=["*"])
    for r in (meta.router, pages.router, auth.router, profile.router, cases.router, leaderboard.router,
              purchases.router, riddle_routes.router, inbox.router, admin.router):
        app.include_router(r)
    return app


app = create_app()
