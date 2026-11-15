"""Players.hidden_at: the admin hides duplicate accounts of one device (15 Nov 2026). A hidden row is off every board and
every count; it is deleted for good 30 days later if nobody used it. Additive, nullable, same on SQLite and PostgreSQL;
skipped when the column already exists (a database created by create_all).

Revision ID: 0038
Revises: 0037
Create Date: 2026-11-15
"""
import sqlalchemy as sa
from alembic import op

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "hidden_at" not in cols:
        op.add_column("players", sa.Column("hidden_at", sa.DateTime, nullable=True))


def downgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "hidden_at" in cols:
        with op.batch_alter_table("players") as b:
            b.drop_column("hidden_at")
