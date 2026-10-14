"""Capacity: indexes for the queries every app start and every solve runs (additive, skipped when they already exist).

 - ix_progress_case_solved (case_id, solved): the solver counts on the case list. It exists in the models, but databases made
   by an older migration chain may not have it.
 - ix_progress_rank (case_id, stars, seconds): the rank of a finished case counts the players that were better; with this
   index it reads only those rows instead of every solver of the case (the 21:00 rush solves thousands of times).

Revision ID: 0022
Revises: 0021
Create Date: 2026-10-14
"""
import sqlalchemy as sa
from alembic import op

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None

INDEXES = [
    ("ix_progress_case_solved", "case_progress", ["case_id", "solved"]),
    ("ix_progress_rank", "case_progress", ["case_id", "stars", "seconds"]),
]


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for name, table, cols in INDEXES:
        if name not in {i["name"] for i in insp.get_indexes(table)}:
            op.create_index(name, table, cols)


def downgrade() -> None:
    insp = sa.inspect(op.get_bind())
    for name, table, _ in reversed(INDEXES):
        if name in {i["name"] for i in insp.get_indexes(table)}:
            op.drop_index(name, table_name=table)
