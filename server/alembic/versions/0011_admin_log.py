"""Admin panel: the admin_log table.

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-11
"""
import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "admin_log" not in sa.inspect(op.get_bind()).get_table_names():
        op.create_table(
            "admin_log",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("at", sa.DateTime(), nullable=False),
            sa.Column("action", sa.String(32), nullable=False),
            sa.Column("target", sa.String(48), nullable=False, server_default=""),
            sa.Column("detail", sa.JSON(), nullable=False),
        )


def downgrade() -> None:
    op.drop_table("admin_log")
