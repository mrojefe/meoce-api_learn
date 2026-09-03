from datetime import datetime, time

from pydantic import BaseModel


class Currency(BaseModel):
    code: str
    name: str
    symbol: str | None
    decimals: int
    usd_exchange_rate: float | None
    last_updated: datetime | None


class CurrencyPreset(BaseModel):
    code: str
    rate_multiplier: float | None
    display_order: int


class Currencies(BaseModel):
    """The body of GET /reference/currencies — two unrelated tables, bundled
    because the same screen (a currency picker) needs both.
    """

    currencies: list[Currency]
    presets: list[CurrencyPreset]


class Sector(BaseModel):
    id: int
    name: str


class Subsector(BaseModel):
    id: int
    sector_id: int
    name: str


class Sectors(BaseModel):
    """The body of GET /reference/sectors."""

    sectors: list[Sector]
    subsectors: list[Subsector]


class Country(BaseModel):
    code: str
    name: str
    region: str | None
    primary_currency_code: str | None


class Exchange(BaseModel):
    id: int
    code: str
    name: str
    country_code: str | None
    currency_code: str | None
    timezone: str
    open_time: time | None
    close_time: time | None
    trading_days: list[int]
    status: str
