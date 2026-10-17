"""Indexes for the admin funnel screen (signups by day, activity by day, last_seen). Additive, each one skipped when it
already exists (a fresh database made by create_all has them).

Revision ID: 0024
Revises: 0023
Create Date: 2026-10-17
"""
import sqlalchemy as sa
from alembic import op

revision = "0024"
down_revision = "0023"
branch_labels = None
depends_on = None

INDEXES = [("ix_players_created_at", "players", ["created_at"]), ("ix_players_last_seen", "players", ["last_seen"]),
           ("ix_progress_opened_at", "case_progress", ["opened_at"]),
           ("ix_progress_finished_at", "case_progress", ["finished_at"])]


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for name, table, cols in INDEXES:
        if name not in {i["name"] for i in insp.get_indexes(table)}:
            op.create_index(name, table, cols)


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for name, table, _ in INDEXES:
        if name in {i["name"] for i in insp.get_indexes(table)}:
            op.drop_index(name, table_name=table)
