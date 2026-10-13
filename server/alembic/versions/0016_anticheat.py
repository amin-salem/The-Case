"""Anti-cheat: proof of investigation, delayed answers, paid invitations.

Revision ID: 0016
Revises: 0015
Create Date: 2026-10-13
"""
import sqlalchemy as sa
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    players = {c["name"] for c in insp.get_columns("players")}
    if "referral_paid" not in players:
        op.add_column("players", sa.Column("referral_paid", sa.Boolean(), nullable=False, server_default=sa.false()))
    progress = {c["name"] for c in insp.get_columns("case_progress")}
    if "ranked" not in progress:
        op.add_column("case_progress", sa.Column("ranked", sa.Boolean(), nullable=False, server_default=sa.true()))
    if "reveal_at" not in progress:
        op.add_column("case_progress", sa.Column("reveal_at", sa.DateTime(), nullable=True))
    if "referral_payouts" not in insp.get_table_names():
        op.create_table(
            "referral_payouts",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("inviter_id", sa.String(32), nullable=False),
            sa.Column("invitee_id", sa.String(32), nullable=False, unique=True),
            sa.Column("device_id", sa.String(128), nullable=False, unique=True),
            sa.Column("week", sa.String(10), nullable=False),
            sa.Column("slot", sa.Integer(), nullable=False),
            sa.Column("paid_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("inviter_id", "week", "slot", name="uq_referral_slot"),
        )
        op.create_index("ix_referral_payouts_inviter_id", "referral_payouts", ["inviter_id"])


def downgrade() -> None:
    pass
