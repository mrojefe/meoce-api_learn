"""Instrument schemas — the declared shape of instrument data."""

from typing import Annotated

from pydantic import BaseModel, Field

from app.core.enums import AllowedSector, AllowedType
from app.schemas.common import Symbol


class InstrumentFilters(BaseModel):
    """The query string of GET /instruments, declared as a model.

    Reading the filters as a model rather than as loose parameters buys one
    thing that matters: `extra="forbid"`. An unknown parameter is refused with
    a 422 naming it, instead of being silently ignored — so `?tpye=stock`
    reports a typo rather than quietly returning the whole list.
    """

    model_config = {"extra": "forbid"}
    type: AllowedType | None = None
    sector:AllowedSector|None = None
    limit: Annotated[int,Field( ge=1, le=100, description="max rows returned")] = 20


class Instrument(BaseModel):
    """One instrument, as this API promises to return it.

    Used as the response model, so it is a contract in both directions: it
    documents `/docs`, and it refuses to serialise a row that does not match.
    A row whose `type` is absent from AllowedType raises here rather than
    reaching the client.

    `sector` is optional because the join that provides it is a LEFT JOIN: an
    instrument attached to no sector is returned with `sector: null` instead of
    disappearing from the list.
    """

    symbol: Symbol 
    name: str
    type: AllowedType
    status: str | None
    sector: AllowedSector | None = None

class InstrumentCreate(BaseModel):
    """The body accepted by POST /instruments.

    Separate from `Instrument` on purpose: what a client may *send* is not what
    the API *returns*. `status` is absent here because it is decided by the
    database, and accepting it from the client would let anyone create a
    delisted instrument.
    """

    symbol: Symbol
    name: str = Field(min_length=2, max_length=120)
    type: AllowedType = AllowedType.STOCK
    sector: AllowedSector| None = AllowedSector.INDUSTRIELS
    



#model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")
#model_config = {"str_strip_whitespace":True}