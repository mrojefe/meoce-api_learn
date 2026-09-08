"""Notification settings routes — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas import notification_settings as schemas
from app.schemas.common import Envelope, ErrorEnvelope
from app.services import notification_settings as services

router = APIRouter(prefix="/notification-settings", tags=["notification-settings"])


@router.get("", response_model=Envelope[schemas.NotificationSettings],
            responses={401: {"model": ErrorEnvelope}})
def get_notification_settings(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the caller's phone and its verification state.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {...}}.
    """
    return {"data": services.get_settings(user_id)}


@router.put("", response_model=Envelope[schemas.NotificationSettings],
            responses={401: {"model": ErrorEnvelope}})
def update_notification_settings(
    user_id: Annotated[str, Depends(get_current_user_id)],
    body: schemas.NotificationSettingsUpdate,
):
    """Sets or clears the caller's phone, resetting verification.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.
        body (NotificationSettingsUpdate): The new phone number, or null.

    Returns:
        dict: {"data": {...}}.
    """
    return {"data": services.update_phone(user_id, body.phone)}
