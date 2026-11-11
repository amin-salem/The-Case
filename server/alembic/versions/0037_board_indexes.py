"""Indexes for the redesigned boards (11 Nov 2026): the all-time board orders and counts by `players.stars_total`, the
streak board by `players.streak`. Additive, same on SQLite and PostgreSQL.

Revision ID: 0037
Revises: 0036
Create Date: 2026-11-11
"""
import sqlalchemy as sa
from alembic import op

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None

_INDEXES = (("ix_players_stars_total", "stars_total"), ("ix_players_streak", "streak"))


def upgrade() -> None:
    # a database created from the models (tests, the CI "old database" step) already has them
    have = {i["name"] for i in sa.inspect(op.get_bind()).get_indexes("players")}
    for name, col in _INDEXES:
        if name not in have:
            op.create_index(name, "players", [col])


def downgrade() -> None:
    for name, _ in _INDEXES:
        op.drop_index(name, table_name="players")
