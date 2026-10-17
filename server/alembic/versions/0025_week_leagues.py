"""Weekly leagues (a snapshot per week) and the one-row-per-week settlement marker. Additive: two new tables, skipped
when they already exist (a database created by create_all).

Revision ID: 0025
Revises: 0024
Create Date: 2026-10-17
"""
import sqlalchemy as sa
from alembic import op

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    names = set(insp.get_table_names())
    if "week_leagues" not in names:
        op.create_table(
            "week_leagues",
            sa.Column("week", sa.String(10), primary_key=True),
            sa.Column("player_id", sa.String(32), primary_key=True),
            sa.Column("league", sa.Integer, nullable=False, server_default="0"),
        )
        op.create_index("ix_week_leagues_week_league", "week_leagues", ["week", "league"])
    if "week_settlements" not in names:
        op.create_table(
            "week_settlements",
            sa.Column("week", sa.String(10), primary_key=True),
            sa.Column("at", sa.DateTime, nullable=False),
            sa.Column("paid", sa.Integer, nullable=False, server_default="0"),
        )


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    names = set(insp.get_table_names())
    if "week_settlements" in names:
        op.drop_table("week_settlements")
    if "week_leagues" in names:
        op.drop_table("week_leagues")
