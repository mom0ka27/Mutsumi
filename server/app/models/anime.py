from sqlalchemy import ColumnElement, Float, ForeignKey, Integer, JSON, String, Text, select
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


def anime_has_content() -> ColumnElement[bool]:
    """Filter for library content: an Anime that has files behind it.

    Subscribing to a show creates its Anime row before anything is downloaded.
    Those placeholders stay reachable by id and through the subscription list,
    but they are not library content -- listing them would show empty cards and
    zero-byte storage rows.
    """
    return Anime.download_hash.is_not(None) | select(Episode.id).where(
        Episode.anime_id == Anime.id
    ).exists()


class Anime(Base):
    __tablename__ = "anime"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    bangumi_id: Mapped[int] = mapped_column(Integer, unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    name_cn: Mapped[str] = mapped_column(String(255), default="")
    summary: Mapped[str] = mapped_column(Text, default="")
    image_url: Mapped[str] = mapped_column(String(1024), default="")
    score: Mapped[float] = mapped_column(Float, default=0)
    episode_count: Mapped[int] = mapped_column(Integer, default=0)
    air_date: Mapped[str] = mapped_column(String(32), default="")
    rank: Mapped[int] = mapped_column(Integer, default=0)
    platform: Mapped[str] = mapped_column(String(128), default="")
    media_type: Mapped[str] = mapped_column(String(32), default="unknown")
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    infobox: Mapped[list[dict[str, str]]] = mapped_column(JSON, default=list)
    # Bangumi's 别名 rows. Release titles use these far more often than the
    # official name, so subscriptions search on them too.
    aliases: Mapped[list[str]] = mapped_column(JSON, default=list)
    download_hash: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)
    series_id: Mapped[int | None] = mapped_column(
        ForeignKey("series.id", ondelete="SET NULL"), nullable=True, index=True
    )

    episodes: Mapped[list["Episode"]] = relationship(
        back_populates="anime",
        cascade="all, delete-orphan",
    )
    series: Mapped["Series | None"] = relationship(back_populates="animes")
    subscription = relationship(
        "Subscription",
        back_populates="anime",
        uselist=False,
        cascade="all, delete-orphan",
    )


class Series(Base):
    __tablename__ = "series"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    animes: Mapped[list[Anime]] = relationship(
        back_populates="series",
        order_by="Anime.id",
    )


class Episode(Base):
    __tablename__ = "episodes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    anime_id: Mapped[int] = mapped_column(ForeignKey("anime.id", ondelete="CASCADE"), index=True)
    index: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(255), default="")
    filename: Mapped[str] = mapped_column(String(1024), default="")
    download_hash: Mapped[str | None] = mapped_column(
        String(40), nullable=True, index=True
    )
    file_hash: Mapped[str | None] = mapped_column(String(32), nullable=True)

    anime: Mapped[Anime] = relationship(back_populates="episodes")
