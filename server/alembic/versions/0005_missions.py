"""Daily missions: the mission_days table, chest columns on players, interrogated suspects on progress.

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

COLUMNS = [
    ("players", sa.Column("last_chest_day", sa.String(10), nullable=False, server_default="")),
    ("players", sa.Column("chest_streak", sa.Integer(), nullable=False, server_default="0")),
    ("players", sa.Column("chests", sa.Integer(), nullable=False, server_default="0")),
    ("case_progress", sa.Column("seen", sa.JSON(), nullable=True)),
]


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for table, column in COLUMNS:
        if column.name not in {c["name"] for c in insp.get_columns(table)}:
            op.add_column(table, column)
    if "mission_days" not in insp.get_table_names():
        op.create_table(
            "mission_days",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("day", sa.String(10), nullable=False),
            sa.Column("counts", sa.JSON(), nullable=False),
            sa.Column("claimed", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.UniqueConstraint("player_id", "day", name="uq_mission_day"),
        )
        op.create_index("ix_mission_days_player_id", "mission_days", ["player_id"])


def downgrade() -> None:
    op.drop_table("mission_days")
    for table, column in reversed(COLUMNS):
        with op.batch_alter_table(table) as batch:
            batch.drop_column(column.name)
