"""Players: what the app reports about itself (version, build, platform, OS, device model).

Revision ID: 0013
Revises: 0012
Create Date: 2026-10-11
"""
import sqlalchemy as sa
from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None

COLUMNS = [
    ("client_version", sa.String(24), "''"),
    ("client_build", sa.Integer(), "0"),
    ("platform", sa.String(16), "''"),
    ("os_version", sa.String(32), "''"),
    ("device_model", sa.String(48), "''"),
]


def upgrade() -> None:
    have = {c["name"] for c in sa.inspect(op.get_bind()).get_columns("players")}
    for name, typ, default in COLUMNS:
        if name not in have:
            op.add_column("players", sa.Column(name, typ, nullable=False, server_default=sa.text(default)))
    if "client_at" not in have:
        op.add_column("players", sa.Column("client_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("players") as b:
        for name in ["client_at"] + [c[0] for c in COLUMNS]:
            b.drop_column(name)
