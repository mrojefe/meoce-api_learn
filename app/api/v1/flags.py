"""Instrument flag routes — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas.common import Envelope, ErrorEnvelope, Symbol, envelope_
from app.schemas.flags import FlagUpsert, InstrumentFlag
from app.services import flags as flags_services

router = APIRouter(prefix="/flags", tags=["flags"])


@router.get("", response_model=Envelope[dict[str, InstrumentFlag]],
            responses={401: {"model": ErrorEnvelope}})
def list_flags(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns every flag the caller has set, keyed by symbol.

    Same reasoning as `GET /watchlists`: `user_id` comes from the token, not
    from a query parameter, so there is no way to ask for someone else's
    flags.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {"SNTS": {"flag_color": "red", "notes": ...}, ...}}.

    Raises:
        UnauthorizedError: No token, or an invalid one (401).

    Examples:
        GET /api/v1/flags   with  Authorization: Bearer <token>
    """
    rows = flags_services.list_flags(user_id=user_id)
    return envelope_(data=rows, count=len(rows))


@router.put("/{symbol}", response_model=Envelope[InstrumentFlag],
            responses={x: {"model": ErrorEnvelope} for x in (401, 404)})
def upsert_flag(
    symbol: Symbol,
    payload: FlagUpsert,
    user_id: Annotated[str, Depends(get_current_user_id)],):
    """Sets the caller's flag on one instrument — creates it, or overwrites it.

    `PUT`, not `POST`+`PATCH`: unlike a watchlist, a flag has no independent
    id to create first. `(user_id, symbol)` already says exactly which flag
    this is, whether it exists yet or not — that is what makes PUT the right
    verb here (PUT means "this is what this resource should be now",
    idempotent by definition: calling it twice with the same body leaves the
    same end state).

    Args:
        symbol (Symbol): The instrument's ticker.
        payload (FlagUpsert): flag_color, and optional notes.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": {"flag_color": ..., "notes": ...}}.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No instrument has this symbol (404).

    Examples:
        PUT /api/v1/flags/SNTS  {"flag_color": "red"}
    """
    row = flags_services.upsert_flag(
        user_id=user_id,
        symbol=symbol,
        flag_color=payload.flag_color,
        notes=payload.notes,
    )
    return envelope_(data=row)


@router.delete("/{symbol}", status_code=204,
               responses={x: {"model": ErrorEnvelope} for x in (401, 404)})
def delete_flag(
    symbol: Symbol,
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    """Removes the caller's flag from one instrument, if there is one.

    204 whether a flag existed or not — same reasoning as
    `DELETE /watchlists/{id}/items/{symbol}`: removing something already
    absent still leaves the world in the state the caller asked for.

    Args:
        symbol (Symbol): The instrument's ticker.
        user_id (str): The authenticated caller, from the token.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No instrument has this symbol (404).

    Examples:
        DELETE /api/v1/flags/SNTS
    """
    flags_services.delete_flag(user_id=user_id, symbol=symbol)
