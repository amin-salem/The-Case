"""Quick riddles: the riddle_answers table.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "riddle_answers" in sa.inspect(op.get_bind()).get_table_names():
        return  # a new database: 0001 already built it from the models
    op.create_table(
        "riddle_answers",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("day", sa.String(10), nullable=False),
        sa.Column("riddle_id", sa.String(16), nullable=False),
        sa.Column("unlocked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("choice", sa.Integer(), nullable=True),
        sa.Column("correct", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("seconds", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("player_id", "day", "riddle_id", name="uq_riddle_answer"),
    )
    op.create_index("ix_riddle_answers_player_id", "riddle_answers", ["player_id"])


def downgrade() -> None:
    op.drop_table("riddle_answers")
