"""Subscription route — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas import subscription as schemas
from app.schemas.common import Envelope, ErrorEnvelope
from app.services import subscription as services

router = APIRouter(prefix="/subscription", tags=["subscription"])


@router.get("", response_model=Envelope[schemas.Subscription],
            responses={401: {"model": ErrorEnvelope}})
def get_subscription(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the caller's own subscription: plan, status, when it ends.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {...}}.
    """
    return {"data": services.get_subscription(user_id)}
