"""case_progress.night1: the player's one try at the night-1 question of a format-3 weekend case. Additive (nullable);
skipped when the column already exists (a database created by create_all).

Revision ID: 0027
Revises: 0026
Create Date: 2026-10-18
"""
import sqlalchemy as sa
from alembic import op

revision = "0027"
down_revision = "0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    if "night1" not in cols:
        op.add_column("case_progress", sa.Column("night1", sa.JSON, nullable=True))


def downgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    if "night1" in cols:
        with op.batch_alter_table("case_progress") as b:
            b.drop_column("night1")
