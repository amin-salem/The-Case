"""Messages hub: players.feed_seen_at (everything older is read).

Revision ID: 0018
Revises: 0017
Create Date: 2026-10-13
"""
import sqlalchemy as sa
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    if "feed_seen_at" not in cols:
        op.add_column("players", sa.Column("feed_seen_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    pass
