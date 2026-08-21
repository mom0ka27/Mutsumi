"""add cached Bangumi aliases to anime

Revision ID: 0007_add_anime_aliases
Revises: 0006_add_subscription_next_episode
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0007_add_anime_aliases"
down_revision: str | None = "0006_add_subscription_next_episode"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    existing = {column["name"] for column in sa.inspect(bind).get_columns("anime")}
    if "aliases" not in existing:
        # Left empty rather than backfilled: the worker fills a row in from
        # Bangumi the first time it sweeps it, which also picks up aliases added
        # upstream after the row was created.
        op.add_column("anime", sa.Column("aliases", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("anime", "aliases")
