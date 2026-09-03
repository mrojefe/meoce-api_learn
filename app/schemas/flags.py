from typing import Annotated

from pydantic import BaseModel, Field

from app.core.reference import FlagColor


class InstrumentFlag(BaseModel):
    """One flag, as returned inside the GET /flags map — no symbol or user_id
    here, since both are already known by context (the dict key, the token).
    """

    flag_color: FlagColor
    notes: str | None = None


class FlagUpsert(BaseModel):
    """The body accepted by PUT /flags/{symbol}.

    `flag_color: FlagColor` instead of a regex pattern — the allowed set now
    lives in one place (`app/core/reference.py`, mirroring the real
    `flag_colors` table) instead of being spelled out again here as a string.
    A bad value still fails as a 422; the error message just comes from
    Pydantic's enum validation instead of a pattern mismatch.
    """

    flag_color: FlagColor
    notes: Annotated[str | None, Field(description="Optional free text.")] = None
