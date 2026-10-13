"""Phone-secured accounts: hashed phone on players, SMS codes table.

Revision ID: 0017
Revises: 0016
Create Date: 2026-10-13
"""
import sqlalchemy as sa
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    cols = {c["name"] for c in insp.get_columns("players")}
    if "phone_hash" not in cols:
        op.add_column("players", sa.Column("phone_hash", sa.String(64), nullable=True))
        op.create_index("uq_players_phone_hash", "players", ["phone_hash"], unique=True)
    if "phone_last4" not in cols:
        op.add_column("players", sa.Column("phone_last4", sa.String(4), nullable=True))
    if "phone_verified_at" not in cols:
        op.add_column("players", sa.Column("phone_verified_at", sa.DateTime(), nullable=True))
    if "phone_codes" not in insp.get_table_names():
        op.create_table(
            "phone_codes",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("phone_hash", sa.String(64), nullable=False),
            sa.Column("purpose", sa.String(8), nullable=False),
            sa.Column("player_id", sa.String(32), nullable=True),
            sa.Column("code_hash", sa.String(64), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("used", sa.Boolean(), nullable=False, server_default=sa.false()),
        )
        op.create_index("ix_phone_codes_phone_hash", "phone_codes", ["phone_hash"])


def downgrade() -> None:
    pass
