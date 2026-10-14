"""Weekend case: remember which evidence cards the player showed to which suspect.

Revision ID: 0021
Revises: 0020
Create Date: 2026-10-14
"""
import sqlalchemy as sa
from alembic import op

revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    if "shows" not in cols:
        op.add_column("case_progress", sa.Column("shows", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("case_progress", "shows")
