"""add anime subscriptions

Revision ID: 0004_add_subscriptions
Revises: 0003_add_episode_download_hash
Create Date: 2026-08-20
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0004_add_subscriptions"
down_revision: str | None = "0003_add_episode_download_hash"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _json_default(value: str) -> sa.TextClause:
    return sa.text(f"'{value}'")


def upgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())

    if "preference_profiles" not in tables:
        op.create_table(
            "preference_profiles",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("name", sa.String(length=128), nullable=False),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("language_mode", sa.String(length=16), nullable=False, server_default="简"),
            sa.Column("language_unknown", sa.String(length=16), nullable=False, server_default="accept"),
            sa.Column("must_include", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("exclude_tokens", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("prefer_resolution", sa.JSON(), nullable=False, server_default=_json_default('["1080p", "2160p"]')),
            sa.Column("prefer_codec", sa.JSON(), nullable=False, server_default=_json_default('["av1", "hevc", "avc"]')),
            sa.Column("prefer_subtitle", sa.JSON(), nullable=False, server_default=_json_default('["日", "无"]')),
            sa.Column("prefer_bitdepth", sa.JSON(), nullable=False, server_default=_json_default('["10bit", "8bit"]')),
            sa.Column("weights", sa.JSON(), nullable=False, server_default=_json_default('{"fansub": 45, "resolution": 22, "codec": 15, "subtitle": 12, "bitdepth": 6}')),
            sa.Column("neutral_score", sa.Float(), nullable=False, server_default="0.5"),
            sa.Column("accept_now_score", sa.Float(), nullable=False, server_default="0.85"),
            sa.Column("grace_hours", sa.Float(), nullable=False, server_default="3.0"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_preference_profiles_id", "preference_profiles", ["id"])

    if "subscriptions" not in tables:
        op.create_table(
            "subscriptions",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("anime_id", sa.Integer(), nullable=False),
            sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("1")),
            sa.Column("profile_id", sa.Integer(), nullable=False),
            sa.Column("fansubs", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("allow_no_fansub", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("search_keywords", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("must_include", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("exclude_keywords", sa.JSON(), nullable=False, server_default=_json_default("[]")),
            sa.Column("use_subject_id", sa.Boolean(), nullable=False, server_default=sa.text("1")),
            sa.Column("resource_types", sa.JSON(), nullable=False, server_default=_json_default('["动画"]')),
            sa.Column("profile_overrides", sa.JSON(), nullable=True),
            sa.Column("episode_offset_override", sa.Integer(), nullable=True),
            sa.Column("cursor_at", sa.DateTime(), nullable=True),
            sa.Column("last_checked_at", sa.DateTime(), nullable=True),
            sa.Column("last_found_at", sa.DateTime(), nullable=True),
            sa.Column("last_error", sa.Text(), nullable=True),
            sa.Column("created_by", sa.Integer(), nullable=False),
            sa.ForeignKeyConstraint(["anime_id"], ["anime.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["profile_id"], ["preference_profiles.id"], ondelete="RESTRICT"),
            sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("anime_id", name="uq_subscriptions_anime_id"),
        )
        op.create_index("ix_subscriptions_id", "subscriptions", ["id"])
        op.create_index("ix_subscriptions_anime_id", "subscriptions", ["anime_id"])
        op.create_index("ix_subscriptions_profile_id", "subscriptions", ["profile_id"])
        op.create_index("ix_subscriptions_created_by", "subscriptions", ["created_by"])

    if "subscription_episodes" not in tables:
        op.create_table(
            "subscription_episodes",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("subscription_id", sa.Integer(), nullable=False),
            sa.Column("episode_index", sa.Integer(), nullable=True),
            sa.Column("resource_id", sa.Integer(), nullable=False),
            sa.Column("resource_title", sa.Text(), nullable=False, server_default=""),
            sa.Column("score", sa.Float(), nullable=False, server_default="0"),
            sa.Column("attributes", sa.JSON(), nullable=False, server_default=_json_default("{}")),
            sa.Column("download_hash", sa.String(length=40), nullable=True),
            sa.Column("state", sa.String(length=32), nullable=False, server_default="candidate"),
            sa.Column("reason", sa.Text(), nullable=True),
            sa.Column("first_seen_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.ForeignKeyConstraint(["subscription_id"], ["subscriptions.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "subscription_id",
                "episode_index",
                "resource_id",
                name="uq_subscription_episode_resource",
            ),
        )
        op.create_index("ix_subscription_episodes_id", "subscription_episodes", ["id"])
        op.create_index(
            "ix_subscription_episodes_subscription_id",
            "subscription_episodes",
            ["subscription_id"],
        )
        op.create_index("ix_subscription_episodes_state", "subscription_episodes", ["state"])
        op.create_index("ix_subscription_episodes_resource_id", "subscription_episodes", ["resource_id"])
        op.create_index(
            "ix_subscription_episodes_subscription_episode_state",
            "subscription_episodes",
            ["subscription_id", "episode_index", "state"],
        )


def downgrade() -> None:
    op.drop_index("ix_subscription_episodes_subscription_episode_state", table_name="subscription_episodes")
    op.drop_index("ix_subscription_episodes_resource_id", table_name="subscription_episodes")
    op.drop_index("ix_subscription_episodes_state", table_name="subscription_episodes")
    op.drop_index("ix_subscription_episodes_subscription_id", table_name="subscription_episodes")
    op.drop_index("ix_subscription_episodes_id", table_name="subscription_episodes")
    op.drop_table("subscription_episodes")

    op.drop_index("ix_subscriptions_created_by", table_name="subscriptions")
    op.drop_index("ix_subscriptions_profile_id", table_name="subscriptions")
    op.drop_index("ix_subscriptions_anime_id", table_name="subscriptions")
    op.drop_index("ix_subscriptions_id", table_name="subscriptions")
    op.drop_table("subscriptions")

    op.drop_index("ix_preference_profiles_id", table_name="preference_profiles")
    op.drop_table("preference_profiles")
