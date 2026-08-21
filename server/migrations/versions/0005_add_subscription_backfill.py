"""add subscription backfill window

Revision ID: 0005_add_subscription_backfill
Revises: 0004_add_subscriptions
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0005_add_subscription_backfill"
down_revision: str | None = "0004_add_subscriptions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {
        column["name"]
        for column in sa.inspect(bind).get_columns("subscriptions")
    }
    if "backfill_after" not in columns:
        op.add_column(
            "subscriptions",
            sa.Column("backfill_after", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    op.drop_column("subscriptions", "backfill_after")
