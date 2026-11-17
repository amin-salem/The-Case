"""Eight leagues instead of four (17 Nov 2026): the stored league of every snapshot row is doubled (0,1,2,3 -> 0,2,4,6),
so every player stays in the league he was in; the marker row (league 0) is unchanged. Data only, no schema change, runs
once (alembic version), same on SQLite and PostgreSQL.

Revision ID: 0039
Revises: 0038
Create Date: 2026-11-17
"""
import sqlalchemy as sa
from alembic import op

revision = "0039"
down_revision = "0038"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "week_leagues" in sa.inspect(op.get_bind()).get_table_names():
        op.execute("UPDATE week_leagues SET league = league * 2")


def downgrade() -> None:
    if "week_leagues" in sa.inspect(op.get_bind()).get_table_names():
        op.execute("UPDATE week_leagues SET league = league / 2 WHERE league % 2 = 0")
