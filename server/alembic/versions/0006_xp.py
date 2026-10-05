"""Detective rank: players.xp. Old players start with XP for the stars they already earned.

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "xp" not in {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}:
        op.add_column("players", sa.Column("xp", sa.Integer(), nullable=False, server_default="0"))
        # roughly what the new rules would have given: 20 XP per star, 5 per case
        op.execute("UPDATE players SET xp = stars_total * 20 + cases_solved * 5")


def downgrade() -> None:
    with op.batch_alter_table("players") as batch:
        batch.drop_column("xp")
