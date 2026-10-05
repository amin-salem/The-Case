"""Fair solving time: case_progress.active_seconds and last_tick_at.

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-06
"""
import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

COLUMNS = [
    sa.Column("active_seconds", sa.Integer(), nullable=False, server_default="0"),
    sa.Column("last_tick_at", sa.DateTime(), nullable=True),
]


def upgrade() -> None:
    have = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    for col in COLUMNS:
        if col.name not in have:
            op.add_column("case_progress", col)


def downgrade() -> None:
    with op.batch_alter_table("case_progress") as batch:
        for col in COLUMNS:
            batch.drop_column(col.name)
