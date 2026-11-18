"""hunt_states: one row per player and «شکار سه‌روزه» (three-day real-time special case, 18 Nov 2026). Additive; skipped when
the table already exists (a database created by create_all). Same on SQLite and PostgreSQL.

Revision ID: 0040
Revises: 0039
Create Date: 2026-11-18
"""
import sqlalchemy as sa
from alembic import op

revision = "0040"
down_revision = "0039"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if "hunt_states" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "hunt_states",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("hunt_id", sa.String(16), nullable=False),
        sa.Column("holds", sa.JSON(), nullable=False),
        sa.Column("early", sa.JSON(), nullable=False),
        sa.Column("accused", sa.String(16), nullable=True),
        sa.Column("evidence", sa.String(16), nullable=True),
        sa.Column("accused_minute", sa.Integer(), nullable=True),
        sa.Column("solved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("stars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("player_id", "hunt_id", name="uq_hunt_state"),
    )
    op.create_index("ix_hunt_states_player_id", "hunt_states", ["player_id"])
    op.create_index("ix_hunt_state_hunt_solved", "hunt_states", ["hunt_id", "solved"])


def downgrade() -> None:
    op.drop_table("hunt_states")
