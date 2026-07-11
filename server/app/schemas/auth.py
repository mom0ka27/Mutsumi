from pydantic import BaseModel

from app.models import PermissionGroup


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    permission_group: PermissionGroup
