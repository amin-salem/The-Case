"""Rate limiter: the rate_hits table (shared counters for the strict limits).

Revision ID: 0012
Revises: 0011
Create Date: 2026-10-11
"""
import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "rate_hits" not in sa.inspect(op.get_bind()).get_table_names():
        op.create_table(
            "rate_hits",
            sa.Column("key", sa.String(160), primary_key=True),
            sa.Column("window_start", sa.Integer(), primary_key=True, autoincrement=False),
            sa.Column("count", sa.Integer(), nullable=False, server_default="0"),
        )
        op.create_index("ix_rate_hits_window_start", "rate_hits", ["window_start"])


def downgrade() -> None:
    op.drop_table("rate_hits")
