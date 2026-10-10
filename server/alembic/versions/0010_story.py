"""Story mode: warrants on players, and the story_progress table.

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-10
"""
import sqlalchemy as sa
from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "warrants" not in {c["name"] for c in insp.get_columns("players")}:
        op.add_column("players", sa.Column("warrants", sa.Integer(), nullable=False, server_default="0"))
    if "story_progress" not in insp.get_table_names():
        op.create_table(
            "story_progress",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("season", sa.Integer(), nullable=False),
            sa.Column("chapter", sa.Integer(), nullable=False),
            sa.Column("opened_at", sa.DateTime(), nullable=False),
            sa.Column("finished_at", sa.DateTime(), nullable=True),
            sa.Column("solved", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("stars", sa.Integer(), nullable=False, server_default="0"),
            sa.UniqueConstraint("player_id", "season", "chapter", name="uq_story_progress"),
        )
        op.create_index("ix_story_progress_player_id", "story_progress", ["player_id"])


def downgrade() -> None:
    op.drop_table("story_progress")
    with op.batch_alter_table("players") as batch:
        batch.drop_column("warrants")
