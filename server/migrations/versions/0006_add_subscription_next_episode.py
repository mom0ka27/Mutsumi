"""add cached next-episode fields to subscriptions

Revision ID: 0006_add_subscription_next_episode
Revises: 0005_add_subscription_backfill
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0006_add_subscription_next_episode"
down_revision: str | None = "0005_add_subscription_backfill"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_COLUMNS: tuple[tuple[str, sa.types.TypeEngine], ...] = (
    ("next_episode_index", sa.Integer()),
    ("next_episode_air_date", sa.DateTime()),
)


def upgrade() -> None:
    bind = op.get_bind()
    existing = {
        column["name"]
        for column in sa.inspect(bind).get_columns("subscriptions")
    }
    for name, column_type in _COLUMNS:
        if name not in existing:
            op.add_column("subscriptions", sa.Column(name, column_type, nullable=True))


def downgrade() -> None:
    for name, _ in _COLUMNS:
        op.drop_column("subscriptions", name)
