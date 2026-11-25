"""kikoja_runs: one row per player and «کی کجا؟» puzzle (25 Nov 2026). Additive; skipped when the table already exists (a
database created by create_all). Same on SQLite and PostgreSQL.

Revision ID: 0041
Revises: 0040
Create Date: 2026-11-25
"""
import sqlalchemy as sa
from alembic import op

revision = "0041"
down_revision = "0040"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "kikoja_runs" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "kikoja_runs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("puzzle_id", sa.String(8), nullable=False),
        sa.Column("mistakes", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("hints", sa.JSON(), nullable=False),
        sa.Column("reopened", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("solved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("stars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("secs", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("reward", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("proof", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("player_id", "puzzle_id", name="uq_kikoja_run"),
    )
    op.create_index("ix_kikoja_runs_player_id", "kikoja_runs", ["player_id"])
    op.create_index("ix_kikoja_run_puzzle_solved", "kikoja_runs", ["puzzle_id", "solved"])


def downgrade() -> None:
    op.drop_table("kikoja_runs")
