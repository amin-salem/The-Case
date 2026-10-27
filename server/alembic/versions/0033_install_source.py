"""players.install_source: the store that installed the app (package name reported by build 79+).
Additive (string, default ''); skipped when it already exists (a database created by create_all). Works on SQLite
and PostgreSQL.

Revision ID: 0033
Revises: 0032
Create Date: 2026-10-27
"""
import sqlalchemy as sa
from alembic import op

revision = "0033"
down_revision = "0032"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "install_source" not in cols:
        op.add_column("players", sa.Column("install_source", sa.String(64), nullable=False, server_default=sa.text("''")))


def downgrade() -> None:
    with op.batch_alter_table("players") as b:
        b.drop_column("install_source")
