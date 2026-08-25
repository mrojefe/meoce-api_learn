"""Instrument schemas — the declared shape of instrument data."""

from typing import Annotated

from pydantic import BaseModel, Field

from app.core.enums import AllowedSector, AllowedType
from app.schemas.common import Symbol


class InstrumentFilters(BaseModel):
    model_config = {"extra": "forbid"}
    type: AllowedType | None = None
    sector:AllowedSector|None = None
    limit: Annotated[int,Field( ge=1, le=100, description="max rows returned")] = 20


class Instrument(BaseModel):
    symbol: Symbol 
    name: str
    type: AllowedType
    status: str | None
    sector: AllowedSector | None = None

class InstrumentCreate(BaseModel):
    symbol: Symbol
    name: str = Field(min_length=2, max_length=120)
    type: AllowedType = AllowedType.STOCK
    sector: AllowedSector| None = AllowedSector.INDUSTRIELS
    



#model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")
#model_config = {"str_strip_whitespace":True}