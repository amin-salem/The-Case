"""Story choices: the player's place, choices, clues and relationships inside a chapter.

Revision ID: 0015
Revises: 0014
Create Date: 2026-10-12
"""
import sqlalchemy as sa
from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "story_state" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "story_state",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("chapter_id", sa.String(8), nullable=False),
        sa.Column("scene", sa.String(24), nullable=False, server_default=sa.text("''")),
        sa.Column("chosen", sa.JSON(), nullable=False),
        sa.Column("clues", sa.JSON(), nullable=False),
        sa.Column("relations", sa.JSON(), nullable=False),
        sa.Column("done", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("player_id", "chapter_id", name="uq_story_state"),
    )
    op.create_index("ix_story_state_player_id", "story_state", ["player_id"])


def downgrade() -> None:
    op.drop_table("story_state")
