"""Right suspect + wrong proof costs a star, not a try: count those misses.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    cols = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("case_progress")}
    if "proof_misses" not in cols:
        op.add_column("case_progress", sa.Column("proof_misses", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    with op.batch_alter_table("case_progress") as batch:
        batch.drop_column("proof_misses")
