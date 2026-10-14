"""Avatars and frames: ownership table, the chosen avatar id and frame on the player.

Revision ID: 0020
Revises: 0019
Create Date: 2026-10-14
"""
import sqlalchemy as sa
from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    cols = {c["name"] for c in insp.get_columns("players")}
    if "avatar_id" not in cols:
        op.add_column("players", sa.Column("avatar_id", sa.String(24), nullable=False, server_default=""))
    if "avatar_frame" not in cols:
        op.add_column("players", sa.Column("avatar_frame", sa.String(24), nullable=False, server_default="frame_brass"))
    if "player_avatars" not in insp.get_table_names():
        op.create_table(
            "player_avatars",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("kind", sa.String(8), nullable=False, server_default="avatar"),
            sa.Column("avatar_id", sa.String(24), nullable=False),
            sa.Column("how", sa.String(8), nullable=False, server_default="goal"),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("player_id", "kind", "avatar_id", name="uq_player_avatar"),
        )
        op.create_index("ix_player_avatars_player_id", "player_avatars", ["player_id"])


def downgrade() -> None:
    op.drop_table("player_avatars")
    op.drop_column("players", "avatar_frame")
    op.drop_column("players", "avatar_id")
