"""Instrument schemas — the declared shape of instrument data."""

from typing import Annotated

from pydantic import BaseModel, Field

from app.core.enums import (
    AllowedCurrencieCode,
    AllowedExchange,
    AllowedSector,
    AllowedSort,
    AllowedType,
)
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
    sector:AllowedSector| None = None
    offset : Annotated[int, Field( ge=0, le=437, description=""" for the pagination ,it between [0, 437]
                                ,this 428 feel convenient for now where the db contain only 438""")
                        ] = 0
    limit: Annotated[int,Field( ge=1, le=100, description="max rows returned between[1,100]")] = 20
    sort: Annotated[AllowedSort | None, Field(
        description="""Column to order the list by. Omitted, rows come back by 
                    symbol. Only columns visible in the response are allowed; 
                    anything else is a 422.""",
        examples=["name", "type"],
    )] = None


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
    type: Annotated [AllowedType, Field(description= "without giving, the default ('stock') will be applied",
            examples=["stock","right"], ),  ] = AllowedType.STOCK
    sector: AllowedSector
    exchange: AllowedExchange 
    currency_code : Annotated[AllowedCurrencieCode | None, 
                            Field(description= """"
                            currency code is not requierd the default 
                            will be allowed from the currency where the exchange is located
                            """), ] = None
    

class InstrumentCheckExchange(BaseModel):
    """The optional `?exchange=` of GET /instruments/{symbol}.

    One field, and a model rather than a bare parameter for two reasons: the
    description reaches `/docs`, and the value is resolved against
    AllowedExchange — so "ngx" arrives at the service as "NGX".

    Optional by design. Requiring it would burden every caller for a problem
    that only exists for symbols listed twice; defaulting it to "BRVM" would
    hide the problem instead — the caller who meant NGX would silently receive
    BRVM prices. Absent and ambiguous therefore means 409, never a guess.
    """

    exchange: Annotated[AllowedExchange | None, Field(
        description= """the exchange is not requiert but keep in 
        mind that differente exchange can have the same symbol 
        so we recommend you to precise because we woon't guess and return error if many fit
        """, )
    ] = None



#model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")
#model_config = {"str_strip_whitespace":True}
