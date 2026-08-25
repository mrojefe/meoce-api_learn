"""Instruments routes - HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Query

from app.schemas import instruments as instruments_schemas
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
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
def get_by_symbol(symbol: str):
    """Returns one instrument by symbol.

    Args:
        symbol (str): BRVM ticker from the path. Case-insensitive.

    Returns:
        dict: {"data": {...}, "meta": {...}}.

    Raises:
        NotFoundError: Raised by the service when the symbol is unknown; the
            registered handler turns it into 404 with the error contract.

    Examples:
        GET /api/v1/instruments/SNTS
    """
    rows= instruments_services.get_by_symbol(symbol=symbol)
   
    return envelope_(data=rows)


@router.post("",status_code=201,response_model=Envelope[instruments_schemas.Instrument])
def create_instrument(payload: instruments_schemas.InstrumentCreate):
    """Creates an instrument and returns it.

    The body is validated against InstrumentCreate before this function runs:
    the symbol is stripped, uppercased and checked against the BRVM ticker
    pattern, so the service receives clean input.

    Args:
        payload (InstrumentCreate): symbol, name, type and optional sector.

    Returns:
        dict: {"data": {...}} — the created instrument, with 201 Created.

    Raises:
        ConflictError: Raised by the service if the symbol already exists;
            becomes 409 in the error contract.

    Examples:
        POST /api/v1/instruments  {"symbol": "ETIT", "name": "Ecobank"}
    """
    rows = instruments_services.create_instrument(symbol=payload.symbol,
                                              name=payload.name,
                                              type_=payload.type,
                                              sector=payload.sector,
                                            )

    return envelope_(data=rows)



