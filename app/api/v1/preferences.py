"""Preferences routes — HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.deps import get_current_user_id
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
from app.schemas.preferences import Preferences, PreferencesUpdate
from app.services import preferences as preferences_services

router = APIRouter(prefix="/preferences", tags=["preferences"])


@router.get("", response_model=Envelope[Preferences],
            responses={401: {"model": ErrorEnvelope}})
def get_preferences(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the caller's preferences, creating them with defaults on their
    first call.

    Same reasoning as every other route here: `user_id` comes from the
    token, never from a query parameter — nobody can read someone else's
    preferences by changing an id in the URL, because there is no id to
    change.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {...}} — every preference column for this user.

    Raises:
        UnauthorizedError: No token, or an invalid one (401).

    Examples:
        GET /api/v1/preferences   with  Authorization: Bearer <token>
    """
    row = preferences_services.get_preferences(user_id=user_id)
    return envelope_(data=row)


@router.patch("", response_model=Envelope[Preferences],
              responses={401: {"model": ErrorEnvelope}})
def update_preferences(
    payload: PreferencesUpdate,
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    """Changes only the preference fields sent, creating the row first if
    this is the caller's first write.

    `payload.model_dump(exclude_unset=True)` builds the dict of only the
    fields present in the request body — Pydantic's own way of answering the
    same question `model_fields_set` answers, filtered down to just those
    keys and their values in one call, since the service takes a dict here
    instead of individual arguments.

    Args:
        payload (PreferencesUpdate): Whichever of the 13 fields the caller
            sent.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": {...}} — every preference column, as it now stands.

    Raises:
        UnauthorizedError: No token or an invalid one (401).

    Examples:
        PATCH /api/v1/preferences  {"default_currency": "USD"}
    """
    fields = payload.model_dump(exclude_unset=True)
    row = preferences_services.update_preferences(user_id=user_id, fields=fields)
    return envelope_(data=row)
