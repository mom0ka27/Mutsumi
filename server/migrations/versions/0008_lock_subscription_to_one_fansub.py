"""replace the fansub priority list with one locked group

Revision ID: 0008_lock_subscription_to_one_fansub
Revises: 0007_add_anime_aliases
Create Date: 2026-08-21
"""

from collections.abc import Sequence
import json

from alembic import op
import sqlalchemy as sa


revision: str = "0008_lock_subscription_to_one_fansub"
down_revision: str | None = "0007_add_anime_aliases"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("subscriptions")}
    if "fansub" not in columns:
        op.add_column(
            "subscriptions",
            sa.Column("fansub", sa.String(128), nullable=False, server_default=""),
        )
    if "fansubs" in columns:
        # The head of the old priority list is the group that was actually
        # winning most episodes, so it becomes the locked one.
        for subscription_id, raw in bind.execute(
            sa.text("select id, fansubs from subscriptions")
        ).fetchall():
            bind.execute(
                sa.text("update subscriptions set fansub = :fansub where id = :id"),
                {"id": subscription_id, "fansub": _first_fansub(raw)},
            )
        with op.batch_alter_table("subscriptions") as batch:
            batch.drop_column("fansubs")


def downgrade() -> None:
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("subscriptions")}
    if "fansubs" not in columns:
        op.add_column("subscriptions", sa.Column("fansubs", sa.JSON(), nullable=True))
    for subscription_id, fansub in bind.execute(
        sa.text("select id, fansub from subscriptions")
    ).fetchall():
        bind.execute(
            sa.text("update subscriptions set fansubs = :fansubs where id = :id"),
            {"id": subscription_id, "fansubs": json.dumps([fansub] if fansub else [])},
        )
    with op.batch_alter_table("subscriptions") as batch:
        batch.drop_column("fansub")


def _first_fansub(raw: object) -> str:
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return ""
    if isinstance(raw, list):
        for item in raw:
            text = str(item or "").strip()
            if text:
                return text
    return ""
