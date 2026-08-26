"""Instruments routes - HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Query

from app.schemas import instruments as instruments_schemas
from app.schemas.common import Envelope, ErrorEnvelope, Symbol, envelope_
from app.services import instruments as instruments_services

router = APIRouter(prefix="/instruments", tags=["instruments"]) 

@router.get("", response_model=Envelope[list[instruments_schemas.Instrument]],
                responses={x:{"model": ErrorEnvelope} for x in [403,]})
def list_instruments(payload: Annotated[instruments_schemas.InstrumentFilters, Query()]):
    """Lists instruments, filtered and paginated.

    The filters arrive as a model read from the query string, so unknown
    parameters are rejected (`extra="forbid"`) instead of being silently
    ignored — a typo like `?tpye=stock` returns 422 rather than the whole list.

    Args:
        payload (InstrumentFilters): type, sector and limit, from the URL.

    Returns:
        dict: {"data": [...], "meta": {"count": N}}, validated against
            Envelope[list[Instrument]] on the way out.

    Examples:
        GET /api/v1/instruments?type=bond&limit=2
    """
    rows , count = instruments_services.list_instruments(type_=payload.type, 
                                                sector=payload.sector , 
                                                limit=payload.limit
                                            )

    return envelope_(data=rows,count=count)



@router.get("/{symbol}", response_model=Envelope[instruments_schemas.Instrument],
            responses={x:{"model": ErrorEnvelope} for x in [404,422]})
def get_by_symbol(symbol:Symbol, exchange: Annotated[instruments_schemas.InstrumentCheckExchange, Query()]):
    """Returns one instrument, identified by symbol and optionally by exchange.

    The two arguments come from two different places, which is why they cannot
    share one model: `symbol` is part of the path, `exchange` is read from the
    query string — hence `Query()` around the model that carries it.

    Args:
        symbol (Symbol): Ticker from the path. Stripped, uppercased and
            pattern-checked by the annotation before this function runs.
        exchange (InstrumentCheckExchange): Carries the optional `?exchange=`
            code. A model rather than a bare parameter so the description
            reaches `/docs` and the value is resolved against AllowedExchange.

    Returns:
        dict: {"data": {...}, "meta": {...}}.

    Raises:
        NotFoundError: Unknown symbol, or unknown symbol/exchange pairing —
            404 through the error contract.
        ConflictError: The symbol exists on several exchanges and none was
            given — 409, listing them, so the caller can retry precisely.

    Examples:
        GET /api/v1/instruments/SNTS?exchange=BRVM
        GET /api/v1/instruments/SNTS          -> 409 if listed twice
    """
    rows= instruments_services.get_by_symbol(symbol=symbol,exchange=exchange.exchange)
   
    return envelope_(data=rows)


@router.post("",status_code=201,response_model=Envelope[instruments_schemas.Instrument])
def create_instrument(payload: instruments_schemas.InstrumentCreate):
    """Creates an instrument and returns the row the database stored.

    The body is validated **and normalised** by InstrumentCreate before this
    function runs: the symbol is stripped and uppercased, and sector, type,
    exchange and currency are resolved to the exact spelling the database
    holds. The service therefore receives canonical values and repeats none of
    that work.

    201 rather than 200, because a new resource exists that did not before.

    Args:
        payload (InstrumentCreate): symbol, name, type, sector and exchange,
            plus an optional currency_code — omitted, the exchange's currency
            is used.

    Returns:
        dict: {"data": {...}} — the created instrument, with 201 Created.

    Raises:
        ConflictError: The symbol already exists on that exchange; becomes 409
            in the error contract.

    Examples:
        POST /api/v1/instruments
        {"symbol": "TESTX", "name": "Test", "type": "stock",
         "sector": "INDUSTRIELS", "exchange": "NGX"}
    """
    rows = instruments_services.create_instrument(symbol=payload.symbol,
                                              name=payload.name,
                                              type_=payload.type,
                                              sector=payload.sector,
                                              exchange=payload.exchange,
                                              currency_code=payload.currency_code,
                                            )

    return envelope_(data=rows)



