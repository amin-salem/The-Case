"""«به نظر تو کیه؟»: the case_guesses table (one first guess per player and case). Additive; skipped when it already
exists (a database created by create_all).

Revision ID: 0031
Revises: 0030
Create Date: 2026-10-24
"""
import sqlalchemy as sa
from alembic import op

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "case_guesses" not in insp.get_table_names():
        op.create_table(
            "case_guesses",
            sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("case_id", sa.String(16), nullable=False),
            sa.Column("suspect", sa.String(16), nullable=False),
            sa.Column("created_at", sa.DateTime, nullable=False),
            sa.UniqueConstraint("player_id", "case_id", name="uq_case_guess"),
        )
        op.create_index("ix_case_guesses_player_id", "case_guesses", ["player_id"])
        op.create_index("ix_case_guess_case", "case_guesses", ["case_id"])


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "case_guesses" in insp.get_table_names():
        op.drop_table("case_guesses")
