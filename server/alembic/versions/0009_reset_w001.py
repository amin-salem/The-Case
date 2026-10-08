"""Give back the tries players used on the weekend case w001 before its last chapter opened.

Accusing a weekend case is now refused until the last chapter is out (the proof cards are in
it); people who accused on the first night lost tries for nothing. Data only, no new columns.

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-08
"""
import sqlalchemy as sa
from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.get_bind().execute(sa.text(
        "UPDATE case_progress SET attempts = 0, proof_misses = 0, failed = :f, first_accused = NULL, "
        "finished_at = NULL WHERE case_id = 'w001' AND solved = :f"), {"f": False})


def downgrade() -> None:
    pass
