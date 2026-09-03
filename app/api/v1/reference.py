"""Reference routes — HTTP only. Public, no authentication required.

Unlike watchlists, flags or preferences, nothing here belongs to a caller —
a currency list is the same fact whoever asks, so there is no
`Depends(get_current_user_id)` anywhere in this file.
"""

from fastapi import APIRouter

from app.schemas.common import Envelope, envelope_
from app.schemas.reference import Country, Currencies, Exchange, Sectors
from app.services import reference as reference_services

router = APIRouter(prefix="/reference", tags=["reference"])


@router.get("/currencies", response_model=Envelope[Currencies])
def list_currencies():
    """Returns every currency, and the rate-conversion presets shown
    alongside them.

    No `user_id` anywhere in this route — a currency's exchange rate is a
    fact about the world, not about the caller.

    Returns:
        dict: {"data": {"currencies": [...], "presets": [...]}}.

    Examples:
        GET /api/v1/reference/currencies
    """
    currencies, presets = reference_services.list_currencies()
    data = {"currencies": currencies, "presets": presets}
    return envelope_(data=data)


@router.get("/sectors", response_model=Envelope[Sectors])
def list_sectors():
    """Returns every sector and every subsector.

    Args: none — public, same as currencies.

    Returns:
        dict: {"data": {"sectors": [...], "subsectors": [...]}}.

    Examples:
        GET /api/v1/reference/sectors
    """
    sectors, subsectors = reference_services.list_sectors()
    data = {"sectors": sectors, "subsectors": subsectors}
    return envelope_(data=data)


@router.get("/countries", response_model=Envelope[list[Country]])
def list_countries():
    """Returns every country.

    Returns:
        dict: {"data": [...], "meta": {"count": N}}.

    Examples:
        GET /api/v1/reference/countries
    """
    countries, count = reference_services.list_countries()
    return envelope_(data=countries, count=count)


@router.get("/exchanges", response_model=Envelope[list[Exchange]])
def list_exchanges():
    """Returns every exchange.

    Returns:
        dict: {"data": [...], "meta": {"count": N}}.

    Examples:
        GET /api/v1/reference/exchanges
    """
    exchanges, count = reference_services.list_exchanges()
    return envelope_(data=exchanges, count=count)
