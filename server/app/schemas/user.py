from pydantic import BaseModel, ConfigDict

from app.models import PermissionGroup


class UserCreate(BaseModel):
    username: str
    password: str
    permission_group: PermissionGroup = PermissionGroup.USER


class UserUpdate(BaseModel):
    username: str | None = None
    password: str | None = None
    permission_group: PermissionGroup | None = None


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    permission_group: PermissionGroup
