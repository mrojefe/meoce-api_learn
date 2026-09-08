"""Entitlements routes — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas import plans as schemas
from app.schemas.common import Envelope, ErrorEnvelope
from app.services import entitlements as services

router = APIRouter(prefix="/entitlements", tags=["entitlements"])


@router.get("", response_model=Envelope[schemas.PlanFeatures],
            responses={401: {"model": ErrorEnvelope}})
def get_entitlements(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the caller's own plan and features.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {...}}.
    """
    return {"data": services.resolve_entitlements(user_id)}
