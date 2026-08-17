"""Instrument schemas — the declared shape of instrument data."""

from pydantic import BaseModel, Field , field_validator
from typing import Annotated
from app.schemas.common import Symbol 

class InstrumentFilters(BaseModel):
    model_config = {"extra": "forbid"}
    type: str|None = None
    sector:str|None = None
    limit: Annotated[int,Field( ge=1, le=100, description="max rows returned")] = 20


class Instrument(BaseModel):
    symbol: Symbol
    name: str
    type: str
    sector: str | None = None

class InstrumentCreate(BaseModel):
    symbol: Symbol
    name: str = Field(min_length=2, max_length=120)
    type: str = Field(default="stock",)
    sector: str | None = None
    



#model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")
#model_config = {"str_strip_whitespace":True}