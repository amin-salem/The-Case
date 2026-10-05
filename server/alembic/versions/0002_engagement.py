"""Login calendar, streak insurance and the "what others thought" stats.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-05

0001 builds the tables from the current models, so on a brand-new database these
columns already exist; each one is only added when it is missing.
"""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

COLUMNS = [
    ("players", sa.Column("login_day", sa.Integer(), nullable=False, server_default="0")),
    ("players", sa.Column("streak_freezes", sa.Integer(), nullable=False, server_default="0")),
    ("case_progress", sa.Column("first_accused", sa.String(16), nullable=True)),
]


def _existing(table: str) -> set[str]:
    return {c["name"] for c in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    for table, column in COLUMNS:
        if column.name not in _existing(table):
            op.add_column(table, column)


def downgrade() -> None:
    for table, column in reversed(COLUMNS):
        if column.name in _existing(table):
            with op.batch_alter_table(table) as batch:
                batch.drop_column(column.name)
