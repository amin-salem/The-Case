"""kikoja_runs.unlocked: a paid «کی کجا؟» level opened for the day (26 Nov 2026). Additive, default false; skipped when the column
already exists (a database created by create_all). Same on SQLite and PostgreSQL.

Revision ID: 0042
Revises: 0041
Create Date: 2026-11-26
"""
import sqlalchemy as sa
from alembic import op

revision = "0042"
down_revision = "0041"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("kikoja_runs")}
    if "unlocked" not in cols:
        op.add_column("kikoja_runs", sa.Column("unlocked", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("kikoja_runs", "unlocked")
