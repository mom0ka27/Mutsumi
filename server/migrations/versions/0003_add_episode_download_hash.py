"""add episode download hash

Revision ID: 0003_add_episode_download_hash
Revises: 0002_add_series_and_media_type
Create Date: 2026-03-29
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_add_episode_download_hash"
down_revision = "0002_series_type"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("episodes")}
    if "download_hash" not in columns:
        with op.batch_alter_table("episodes") as batch_op:
            batch_op.add_column(sa.Column("download_hash", sa.String(length=40), nullable=True))
            batch_op.create_index("ix_episodes_download_hash", ["download_hash"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("episodes") as batch_op:
        batch_op.drop_index("ix_episodes_download_hash")
        batch_op.drop_column("download_hash")
