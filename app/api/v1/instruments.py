"""Instruments routes - HTTP only. The work happens in the service."""

from fastapi import APIRouter, Query
from app.services import instruments as instruments_service

router = APIRouter(prefix="/instruments", tags=["instruments"]) 

@router.get("")
def list_instruments(
    type: str | None = None,
    sector: str | None = None,
    limit:int = Query(default=20, ge=1, le=100, description="max rows returned"),
):
    rows = instruments_service.list_instruments(type_=type, sector=sector , limit=limit)
    return {"data": rows, "count": len(rows)}