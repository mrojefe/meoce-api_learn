"""Instruments routes - HTTP only. The work happens in the service."""

from typing import Annotated
from fastapi import APIRouter, Query  
from app.services import instruments as instruments_services
from app.schemas  import  instruments as instruments_schemas


router = APIRouter(prefix="/instruments", tags=["instruments"]) 

@router.get("", response_model=list[instruments_schemas.Instrument])
def list_instruments(payload: Annotated[instruments_schemas.InstrumentFilters,Query()]):
    rows = instruments_services.list_instruments(type_=payload.type, 
                                                sector=payload.sector , 
                                                limit=payload.limit
                                            )
    return rows

@router.get("/{symbol}", response_model=instruments_schemas.Instrument)
def get_by_symbol (
    symbol: str,
):  
    rows= instruments_services.get_by_symbol(symbol=symbol)
   
    return rows


@router.post("",status_code=201,response_model=instruments_schemas.Instrument)
def create_instrument(payload: instruments_schemas.InstrumentCreate):

    result= instruments_services.create_instrument(symbol=payload.symbol,
                                              name=payload.name,
                                              type_=payload.type,
                                              sector=payload.sector,
                                            )

    return result
