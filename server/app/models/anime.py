from sqlalchemy import Float, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


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
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    infobox: Mapped[list[dict[str, str]]] = mapped_column(JSON, default=list)
    download_hash: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)

    episodes: Mapped[list["Episode"]] = relationship(
        back_populates="anime",
        cascade="all, delete-orphan",
    )


class Episode(Base):
    __tablename__ = "episodes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    anime_id: Mapped[int] = mapped_column(ForeignKey("anime.id", ondelete="CASCADE"), index=True)
    index: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(255), default="")
    filename: Mapped[str] = mapped_column(String(1024), default="")
    file_hash: Mapped[str | None] = mapped_column(String(32), nullable=True)

    anime: Mapped[Anime] = relationship(back_populates="episodes")
