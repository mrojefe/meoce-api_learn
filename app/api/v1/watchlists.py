"""Watchlist routes — HTTP only. The work happens in the service.

The first user-owned resource in this API. Everything before it was public
reference data, where the answer is the same whoever asks. A watchlist belongs
to one person, so every route here starts by learning who is calling.
"""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_entitlements, get_current_user_id
from app.schemas import watchlists as watchlists_schemas
from app.schemas.common import Envelope, ErrorEnvelope, Symbol, envelope_
from app.schemas.plans import PlanFeatures
from app.services import watchlists as watchlists_services

router = APIRouter(prefix="/watchlists", tags=["watchlists"])


@router.get("", response_model=Envelope[list[watchlists_schemas.Watchlist]],
            responses={401: {"model": ErrorEnvelope}})
def list_watchlists(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the watchlists belonging to the caller.

    Note what the signature does NOT contain: any way for the caller to say
    whose lists they want. There is no `?user_id=`, and there never will be —
    a parameter the caller chooses is a request, not a fact, and anyone could
    ask for anyone's lists.

    The id arrives instead from `get_current_user_id`, which got it out of a
    signed token. That is the difference between identity that is *proven* and
    identity that is merely *claimed*.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.
            The route never reads it from the request itself.

    Returns:
        dict: {"data": [...], "meta": {"count": N}}.

    Raises:
        UnauthorizedError: No token, or an invalid one — 401 before this
            function runs at all.

    Examples:
        GET /api/v1/watchlists   with  Authorization: Bearer <token>
    """
    rows, count = watchlists_services.list_watchlists(user_id=user_id)
    return envelope_(data=rows, count=count)


@router.get("/{watchlist_id}/items",
            response_model=Envelope[list[watchlists_schemas.WatchlistItem]],
            responses={x: {"model": ErrorEnvelope} for x in (401, 403, 404)})
def list_watchlist_items(
    watchlist_id: UUID,
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    """Returns the instruments inside one watchlist.

    Unlike every other route on this router, a non-owner CAN reach this one
    — if the list is public. `_require_ownership(read_only=True)` in the
    service is what allows that; every write route still requires the
    caller to be the owner.

    Args:
        watchlist_id (UUID): The list to read.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": [...], "meta": {"count": N}}.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No such watchlist (404).
        ForbiddenError: The watchlist belongs to someone else and is not
            public (403).

    Examples:
        GET /api/v1/watchlists/5d5ee2a6-75b7-48f8-9e20-68b6ecb62028/items
    """
    rows, count = watchlists_services.list_watchlist_items(
        user_id=user_id, watchlist_id=watchlist_id,
    )
    return envelope_(data=rows, count=count)


@router.post("", status_code=201,
             response_model=Envelope[watchlists_schemas.Watchlist],
             responses={x: {"model": ErrorEnvelope} for x in (401, 403)})
def create_watchlist(
    payload: watchlists_schemas.WatchlistCreate,
    user_id: Annotated[str, Depends(get_current_user_id)],
    entitlements: Annotated[PlanFeatures, Depends(get_current_entitlements)],):
    """Creates a watchlist for the caller, if their plan still allows one.

    Two dependencies, two different questions: `get_current_user_id` asks *who*,
    `get_current_entitlements` asks *what may they*. FastAPI resolves both
    before this function runs, and the second depends on the first — the plan
    is looked up from the id that came out of the token.

    Note what the body cannot contain: an owner. `WatchlistCreate` has name,
    description and is_public, and nothing else. The owner comes from the token,
    so there is no way to express "create this in someone else's account".

    Args:
        payload (WatchlistCreate): name, optional description, is_public.
        user_id (str): The caller, from the token.
        entitlements (PlanFeatures): The caller's plan.

    Returns:
        dict: {"data": {...}} with 201 Created — the row the database wrote,
            id included, since the client needs it for every later call.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        ForbiddenError: The plan's watchlist limit is reached (403).

    Examples:
        POST /api/v1/watchlists  {"name": "BRVM banks"}
    """
    row = watchlists_services.create_watchlist(
        user_id=user_id,
        name=payload.name,
        description=payload.description,
        is_public=payload.is_public,
        entitlements=entitlements,
    )
    return envelope_(data=row)


@router.post("/{watchlist_id}/items", status_code=201,
             responses={x: {"model": ErrorEnvelope} for x in (401, 403, 404, 409)})
def add_item(
    watchlist_id: UUID,
    payload: watchlists_schemas.WatchlistItemAdd,
    user_id: Annotated[str, Depends(get_current_user_id)]):
    """Adds one instrument to one of the caller's watchlists.

    `symbol` comes from the body here, via `WatchlistItemAdd` — unlike the
    DELETE route, where it sits in the URL. Both are defensible; this one
    matches what the real API does for the same endpoint.

    201, not 204: something new now exists. There is nothing meaningful to
    return in the body though — `add_watchlist_symbol` returns `None` — so
    this is 201 with an empty body.

    Args:
        watchlist_id (UUID): The list to add the item to.
        payload (WatchlistItemAdd): The symbol to add.
        user_id (str): The authenticated caller, from the token.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No such watchlist, or no instrument with that symbol
            (404).
        ForbiddenError: The watchlist belongs to someone else (403).
        ConflictError: The symbol is already in this watchlist (409).

    Examples:
        POST /api/v1/watchlists/5d5ee2a6-.../items  {"symbol": "SNTS"}
    """
    watchlists_services.add_watchlist_symbol(user_id, watchlist_id, payload.symbol)


@router.patch("/{watchlist_id}",
              response_model=Envelope[watchlists_schemas.Watchlist],
              responses={x: {"model": ErrorEnvelope} for x in (401, 403, 404)})
def update_watchlist(
    watchlist_id: UUID,
    payload: watchlists_schemas.WatchlistUpdate,
    user_id: Annotated[str, Depends(get_current_user_id)]):
    """Changes only the fields sent, on one of the caller's watchlists.

    `payload.model_fields_set` is what makes this a PATCH rather than a PUT:
    it is the set of field names that were actually present in the request
    body. A field left out of the JSON stays out of the SQL entirely, so an
    omitted `description` keeps its old value instead of being wiped to NULL
    — the trap a naive "just UPDATE every column" version would fall into.

    Args:
        watchlist_id (UUID): The list to update.
        payload (WatchlistUpdate): Whichever of name/description/is_public
            the caller sent.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": {...}} — the row as it now stands.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No such watchlist (404).
        ForbiddenError: The watchlist belongs to someone else (403).

    Examples:
        PATCH /api/v1/watchlists/5d5ee2a6-...  {"name": "BRVM tech"}
    """
    row = watchlists_services.update_watchlist(
        user_id=user_id,
        watchlist_id=watchlist_id,
        fields_set=payload.model_fields_set,
        name=payload.name,
        description=payload.description,
        is_public=payload.is_public,
    )
    return envelope_(data=row)


@router.delete("/{watchlist_id}", status_code=204)
def delete_watchlist(
    watchlist_id: UUID,
    user_id: Annotated[str, Depends(get_current_user_id)],):
    """Deletes one of the caller's watchlists.

    204 No Content on success — a DELETE that worked has nothing left to
    describe, so there is no `data` to wrap in an envelope and no
    `response_model` to declare.

    `watchlist_id: UUID` means FastAPI rejects a malformed id with a 422
    before this function runs, rather than sending a bad value into SQL.

    Args:
        watchlist_id (UUID): The list to delete.
        user_id (str): The authenticated caller, from the token.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No such watchlist (404).
        ForbiddenError: The watchlist belongs to someone else (403).

    Examples:
        DELETE /api/v1/watchlists/5d5ee2a6-75b7-48f8-9e20-68b6ecb62028
    """
    watchlists_services.delete_watchlist(user_id, watchlist_id)


@router.delete("/{watchlist_id}/items/{symbol}", status_code=204)
def remove_item(
    watchlist_id: UUID,
    symbol: Symbol,
    user_id: Annotated[str, Depends(get_current_user_id)],):
    """Removes one instrument from one of the caller's watchlists.

    204 whether the symbol was in the list or not — see the service docstring
    for why: removing something already absent still leaves the world in the
    state the caller asked for.

    `symbol: Symbol` reuses the same normalising type instruments already use,
    so `?/watchlists/{id}/items/snts` and `.../SNTS` reach the service as the
    same value.

    Args:
        watchlist_id (UUID): The list to remove the item from.
        symbol (Symbol): The instrument's ticker.
        user_id (str): The authenticated caller, from the token.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        NotFoundError: No such watchlist, or no instrument with that symbol
            (404).
        ForbiddenError: The watchlist belongs to someone else (403).

    Examples:
        DELETE /api/v1/watchlists/5d5ee2a6-.../items/SNTS
    """
    watchlists_services.remove_watchlist_symbol(user_id, watchlist_id, symbol)

