"""Case comments with 1-5 stars and replies (admin approves before anyone sees them).

Revision ID: 0014
Revises: 0013
Create Date: 2026-10-12
"""
import sqlalchemy as sa
from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "case_comments" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "case_comments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("case_id", sa.String(16), nullable=False),
        sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("parent_id", sa.Integer(), nullable=True),
        sa.Column("slot", sa.String(32), nullable=False, server_default=sa.text("'root'")),
        sa.Column("rating", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("body", sa.String(400), nullable=False, server_default=sa.text("''")),
        sa.Column("status", sa.String(10), nullable=False, server_default=sa.text("'pending'")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("case_id", "player_id", "slot", name="uq_comment_slot"),
    )
    op.create_index("ix_comments_case_status", "case_comments", ["case_id", "status", "id"])
    op.create_index("ix_comments_status", "case_comments", ["status", "id"])
    op.create_index("ix_comments_parent", "case_comments", ["parent_id"])
    op.create_index("ix_case_comments_player_id", "case_comments", ["player_id"])


def downgrade() -> None:
    op.drop_table("case_comments")
