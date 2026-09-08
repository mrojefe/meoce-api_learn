"""Drawings routes — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.core.security.deps import get_current_user_id
from app.schemas import drawings as schemas
from app.schemas.common import Envelope, ErrorEnvelope, Symbol
from app.services import drawings as services

router = APIRouter(prefix="/drawings", tags=["drawings"])


@router.get("", response_model=Envelope[list[schemas.Drawing]],
            responses={401: {"model": ErrorEnvelope}})
def get_drawings(
    user_id: Annotated[str, Depends(get_current_user_id)],
    symbol: Annotated[Symbol | None, Query()] = None,
):
    """Returns the caller's own drawings, symbol optional.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.
        symbol (Symbol | None): Restrict to one instrument.

    Returns:
        dict: {"data": [...]}.
    """
    return {"data": services.get_drawings(user_id, symbol)}


@router.put("", response_model=Envelope[int],
            responses={401: {"model": ErrorEnvelope}})
def upsert_drawings(user_id: Annotated[str, Depends(get_current_user_id)],
                     body: schemas.DrawingsUpsert):
    """Inserts or overwrites a batch of the caller's own drawings.

    Args:
        body (DrawingsUpsert): The drawings to write.
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": <count written>}.
    """
    count = services.upsert_drawings(
        user_id, [d.model_dump() for d in body.drawings]
    )
    return {"data": count}


@router.delete("", response_model=Envelope[None],
                responses={401: {"model": ErrorEnvelope}})
def delete_drawings(user_id: Annotated[str, Depends(get_current_user_id)],
                     body: schemas.DrawingsDelete):
    """Tombstones the caller's own drawings.

    Args:
        body (DrawingsDelete): The drawing ids to tombstone.
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": null}.
    """
    services.delete_drawings(user_id, [str(i) for i in body.ids])
    return {"data": None}
