"""Index on coin_log.reason (10 Nov 2026): the admin block «بروزرسانی اپ» counts the update thank-you grants
(`reason = 'update_bonus:<latest>'`) and the promo impact table counts `promo:<case>` rows; without an index both read the whole
ledger. Additive, same on SQLite and PostgreSQL.

Revision ID: 0036
Revises: 0035
Create Date: 2026-11-10
"""
from alembic import op

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index("ix_coin_log_reason", "coin_log", ["reason"])


def downgrade() -> None:
    op.drop_index("ix_coin_log_reason", table_name="coin_log")
