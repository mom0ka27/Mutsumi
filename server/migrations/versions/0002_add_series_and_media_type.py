"""add series and media type

Revision ID: 0002_series_type
Revises: 0001_initial
Create Date: 2026-07-29
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0002_series_type"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "series" not in tables:
        op.create_table(
            "series",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.PrimaryKeyConstraint("id"),
        )
        with op.batch_alter_table("series", schema=None) as batch_op:
            batch_op.create_index(batch_op.f("ix_series_id"), ["id"], unique=False)

    columns = {column["name"] for column in sa.inspect(bind).get_columns("anime")}
    if "media_type" not in columns:
        with op.batch_alter_table("anime", schema=None) as batch_op:
            batch_op.add_column(
                sa.Column(
                    "media_type",
                    sa.String(length=32),
                    nullable=False,
                    server_default="unknown",
                )
            )
    if "series_id" not in columns:
        with op.batch_alter_table("anime", schema=None) as batch_op:
            batch_op.add_column(sa.Column("series_id", sa.Integer(), nullable=True))
            batch_op.create_index(
                batch_op.f("ix_anime_series_id"), ["series_id"], unique=False
            )
            batch_op.create_foreign_key(
                "fk_anime_series_id_series",
                "series",
                ["series_id"],
                ["id"],
                ondelete="SET NULL",
            )


def downgrade() -> None:
    with op.batch_alter_table("anime", schema=None) as batch_op:
        batch_op.drop_constraint("fk_anime_series_id_series", type_="foreignkey")
        batch_op.drop_index(batch_op.f("ix_anime_series_id"))
        batch_op.drop_column("series_id")
        batch_op.drop_column("media_type")
    with op.batch_alter_table("series", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_series_id"))
    op.drop_table("series")
