"""Rank thresholds raised (1 Nov 2026, Amin: the gaps between ranks were too small). Data only, no schema change.
Nobody loses a rank: every player below the NEW threshold of the rank they hold under the OLD table is lifted to that
threshold (their progress inside the rank starts again at its bottom). NOT safe to run twice by hand (the second run
would lift again); Alembic runs it once. Same SQL on SQLite and PostgreSQL.

Revision ID: 0035
Revises: 0034
Create Date: 2026-11-01
"""
from alembic import op

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None


# highest old rank first: the first WHEN that matches is the rank the player holds today
SQL = """UPDATE players SET xp = CASE
        WHEN xp >= 30000 AND xp < 50000 THEN 50000
        WHEN xp >= 20000 AND xp < 36000 THEN 36000
        WHEN xp >= 15000 AND xp < 29000 THEN 29000
        WHEN xp >= 12500 AND xp < 24000 THEN 24000
        WHEN xp >= 10000 AND xp < 20000 THEN 20000
        WHEN xp >= 8000 AND xp < 16500 THEN 16500
        WHEN xp >= 6500 AND xp < 13500 THEN 13500
        WHEN xp >= 5300 AND xp < 11000 THEN 11000
        WHEN xp >= 4200 AND xp < 9000 THEN 9000
        WHEN xp >= 3300 AND xp < 7200 THEN 7200
        WHEN xp >= 2500 AND xp < 5600 THEN 5600
        WHEN xp >= 1900 AND xp < 4300 THEN 4300
        WHEN xp >= 1300 AND xp < 3200 THEN 3200
        WHEN xp >= 900 AND xp < 2300 THEN 2300
        WHEN xp >= 600 AND xp < 1600 THEN 1600
        WHEN xp >= 400 AND xp < 1000 THEN 1000
        WHEN xp >= 200 AND xp < 550 THEN 550
        WHEN xp >= 100 AND xp < 250 THEN 250
        ELSE xp END
    WHERE xp >= 100"""


def upgrade() -> None:
    op.execute(SQL)


def downgrade() -> None:
    pass  # the lifted XP stays (it cannot be told apart from XP earned)
