"""Index for the invite status (`GET /v1/referrals/status` lists the players one player invited). Additive, skipped
when it already exists.

Revision ID: 0023
Revises: 0022
Create Date: 2026-10-15
"""
import sqlalchemy as sa
from alembic import op

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None

NAME = "ix_players_referred_by"


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if NAME not in {i["name"] for i in insp.get_indexes("players")}:
        op.create_index(NAME, "players", ["referred_by"])


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if NAME in {i["name"] for i in insp.get_indexes("players")}:
        op.drop_index(NAME, table_name="players")
