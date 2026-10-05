"""Achievements: player_achievements table and lifetime counters (players.stats).

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "stats" not in {c["name"] for c in insp.get_columns("players")}:
        op.add_column("players", sa.Column("stats", sa.JSON(), nullable=True))
    if "player_achievements" not in insp.get_table_names():
        op.create_table(
            "player_achievements",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("achievement_id", sa.String(32), nullable=False),
            sa.Column("at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("player_id", "achievement_id", name="uq_player_achievement"),
        )
        op.create_index("ix_player_achievements_player_id", "player_achievements", ["player_id"])


def downgrade() -> None:
    op.drop_table("player_achievements")
    with op.batch_alter_table("players") as batch:
        batch.drop_column("stats")
