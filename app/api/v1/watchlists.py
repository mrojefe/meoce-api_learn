"""Watchlist routes — HTTP only. The work happens in the service.

The first user-owned resource in this API. Everything before it was public
reference data, where the answer is the same whoever asks. A watchlist belongs
to one person, so every route here starts by learning who is calling.
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas import watchlists as watchlists_schemas
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
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
