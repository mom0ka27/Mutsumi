from pydantic import BaseModel


class SetupStatus(BaseModel):
    initialized: bool
    server_name: str


class SetupCreate(BaseModel):
    username: str
    password: str
    server_name: str | None = None
