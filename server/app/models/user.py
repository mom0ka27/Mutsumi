from enum import StrEnum

from sqlalchemy import Enum, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class PermissionGroup(StrEnum):
    ADMIN = "Admin"
    USER = "User"
    GUEST = "Guest"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    permission_group: Mapped[PermissionGroup] = mapped_column(
        Enum(PermissionGroup), default=PermissionGroup.USER
    )
