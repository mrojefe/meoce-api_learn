from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel

from app.schemas.common import Symbol


class Drawing(BaseModel):
    """One drawing, as this API returns it."""

    id: UUID
    symbol: Symbol
    payload: dict[str, Any]
    updated_at: datetime
    deleted_at: datetime | None


class DrawingIn(BaseModel):
    """One drawing, as PUT /drawings accepts it. No `user_id` — the owner
    comes from the token, never the body.
    """

    id: UUID
    symbol: Symbol
    payload: dict[str, Any]


class DrawingsUpsert(BaseModel):
    """The body accepted by PUT /drawings."""

    drawings: list[DrawingIn]


class DrawingsDelete(BaseModel):
    """The body accepted by DELETE /drawings."""

    ids: list[UUID]
