"""Streak repair: players.streak_repair_mark and the streak_repairs table (unique per player and break). Additive;
each part is skipped when it already exists (a database created by create_all).

Revision ID: 0028
Revises: 0027
Create Date: 2026-10-20
"""
import sqlalchemy as sa
from alembic import op

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "streak_repair_mark" not in {c["name"] for c in insp.get_columns("players")}:
        op.add_column("players", sa.Column("streak_repair_mark", sa.String(10), nullable=False, server_default=""))
    if "streak_repairs" not in insp.get_table_names():
        op.create_table(
            "streak_repairs",
            sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("broken_after", sa.String(10), nullable=False),
            sa.Column("streak", sa.Integer, nullable=False, server_default="0"),
            sa.Column("price", sa.Integer, nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime, nullable=False),
            sa.UniqueConstraint("player_id", "broken_after", name="uq_streak_repair"),
        )
        op.create_index("ix_streak_repairs_player_id", "streak_repairs", ["player_id"])


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "streak_repairs" in insp.get_table_names():
        op.drop_table("streak_repairs")
    if "streak_repair_mark" in {c["name"] for c in insp.get_columns("players")}:
        with op.batch_alter_table("players") as b:
            b.drop_column("streak_repair_mark")
