"""nickname_claims: unique detective names (app/nicknames.py). Additive (a new table); skipped when it already exists
(a database created by create_all). Existing names are claimed once, for the OLDEST account that has them; the random
default names «کارآگاه1234» are never claimed. Works on SQLite and PostgreSQL.

Revision ID: 0034
Revises: 0033
Create Date: 2026-10-28
"""
import sqlalchemy as sa
from alembic import op

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if "nickname_claims" in sa.inspect(bind).get_table_names():
        return
    claims = op.create_table(
        "nickname_claims",
        sa.Column("key", sa.String(40), primary_key=True),
        sa.Column("player_id", sa.String(32), nullable=False),
        sa.Column("created_at", sa.DateTime, nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_nickname_claims_player_id", "nickname_claims", ["player_id"])
    from app.nicknames import is_default, nickname_key

    players = sa.table("players", sa.column("id", sa.String), sa.column("nickname", sa.String), sa.column("created_at", sa.DateTime))
    seen: set[str] = set()
    batch: list[dict] = []
    for pid, name in bind.execute(sa.select(players.c.id, players.c.nickname).where(players.c.nickname != "")
                                  .order_by(players.c.created_at, players.c.id)):
        if is_default(name):
            continue
        key = nickname_key(name)
        if key in seen:
            continue   # a later account with the same name keeps it, unclaimed, until it renames
        seen.add(key)
        batch.append({"key": key, "player_id": pid})
        if len(batch) >= 500:
            bind.execute(claims.insert(), batch)
            batch = []
    if batch:
        bind.execute(claims.insert(), batch)


def downgrade() -> None:
    op.drop_table("nickname_claims")
