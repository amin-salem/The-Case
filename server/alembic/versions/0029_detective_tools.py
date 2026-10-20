"""Detective tools: the player_tools stock and the case_tool_uses record (unique per player, case and kind). Additive;
each table is skipped when it already exists (a database created by create_all).

Revision ID: 0029
Revises: 0028
Create Date: 2026-10-20
"""
import sqlalchemy as sa
from alembic import op

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    if "player_tools" not in insp.get_table_names():
        op.create_table(
            "player_tools",
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
            sa.Column("kind", sa.String(16), primary_key=True),
            sa.Column("count", sa.Integer, nullable=False, server_default="0"),
            sa.Column("free_used", sa.Boolean, nullable=False, server_default=sa.false()),
        )
    if "case_tool_uses" not in insp.get_table_names():
        op.create_table(
            "case_tool_uses",
            sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
            sa.Column("player_id", sa.String(32), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
            sa.Column("case_id", sa.String(16), nullable=False),
            sa.Column("kind", sa.String(16), nullable=False),
            sa.Column("source", sa.String(8), nullable=False),
            sa.Column("result", sa.JSON, nullable=False),
            sa.Column("created_at", sa.DateTime, nullable=False),
            sa.UniqueConstraint("player_id", "case_id", "kind", name="uq_case_tool_use"),
        )
        op.create_index("ix_case_tool_uses_player_id", "case_tool_uses", ["player_id"])


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for t in ("case_tool_uses", "player_tools"):
        if t in insp.get_table_names():
            op.drop_table(t)
