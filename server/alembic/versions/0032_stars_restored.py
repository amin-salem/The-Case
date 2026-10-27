"""case_progress.stars_restored: marks a solve whose stars were given back once (POST /admin/anticheat-restore).
Additive (boolean, default false); skipped when it already exists (a database created by create_all). Works on SQLite
and PostgreSQL.

Revision ID: 0032
Revises: 0031
Create Date: 2026-10-25
"""
import sqlalchemy as sa
from alembic import op

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    cols = {c["name"] for c in insp.get_columns("case_progress")}
    if "stars_restored" not in cols:
        op.add_column("case_progress", sa.Column("stars_restored", sa.Boolean, nullable=False,
                                                 server_default=sa.false()))


def downgrade() -> None:
    pass
