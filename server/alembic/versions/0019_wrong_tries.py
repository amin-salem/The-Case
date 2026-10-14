"""Case progress remembers the wrong accusations (suspect, evidence, kind) so the app can mark them in red.

Revision ID: 0019
Revises: 0018
Create Date: 2026-10-14
"""
import sqlalchemy as sa
from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    if "wrong_tries" not in cols:
        op.add_column("case_progress", sa.Column("wrong_tries", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("case_progress", "wrong_tries")
