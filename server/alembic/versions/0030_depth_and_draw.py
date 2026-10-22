"""Investigation depth (case_progress.cards_opened / questions_asked) and the daily draw table. Additive only; each
piece is skipped when it already exists (a database created by create_all).

Revision ID: 0030
Revises: 0029
Create Date: 2026-10-22
"""
import sqlalchemy as sa
from alembic import op

revision = "0030"
down_revision = "0029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    cols = {c["name"] for c in insp.get_columns("case_progress")}
    if "cards_opened" not in cols:
        op.add_column("case_progress", sa.Column("cards_opened", sa.JSON, nullable=True))
    if "questions_asked" not in cols:
        op.add_column("case_progress", sa.Column("questions_asked", sa.JSON, nullable=True))
    if "daily_draws" not in insp.get_table_names():
        op.create_table(
            "daily_draws",
            sa.Column("case_id", sa.String(16), primary_key=True),
            sa.Column("winner_id", sa.String(32), nullable=True),
            sa.Column("eligible", sa.Integer, nullable=False, server_default="0"),
            sa.Column("at", sa.DateTime, nullable=False),
        )


def downgrade() -> None:
    pass
