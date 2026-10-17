"""Players.tester: the admin marks app testers (story open for them, hidden from leaderboards). Additive, default false;
skipped when the column already exists (a database created by create_all).

Revision ID: 0026
Revises: 0025
Create Date: 2026-10-17
"""
import sqlalchemy as sa
from alembic import op

revision = "0026"
down_revision = "0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "tester" not in cols:
        op.add_column("players", sa.Column("tester", sa.Boolean, nullable=False, server_default=sa.false()))


def downgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "tester" in cols:
        with op.batch_alter_table("players") as b:
            b.drop_column("tester")
