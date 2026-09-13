"""User profile routes — HTTP only. The work happens in the service.

`/users/me` — always "me", never `/users/{id}`. There is no way to reach
anyone else's profile through this router.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.core.security.deps import get_current_user_id
from app.schemas import user_profile as schemas
from app.schemas import whatsapp_auth as whatsapp_schemas
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
from app.services import user_profile as services
from app.services import whatsapp as whatsapp_services

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=Envelope[schemas.UserProfile],
            responses={401: {"model": ErrorEnvelope}})
def get_profile(user_id: Annotated[str, Depends(get_current_user_id)]):
    """Returns the caller's own profile.

    Args:
        user_id (str): The authenticated caller, injected by the dependency.

    Returns:
        dict: {"data": {...}}.

    Raises:
        UnauthorizedError: No token, or an invalid one (401).

    Examples:
        GET /api/v1/users/me   with  Authorization: Bearer <token>
    """
    row = services.get_profile(user_id=user_id)
    return envelope_(data=row)


@router.patch("/me", response_model=Envelope[schemas.UserProfile],
              responses={x: {"model": ErrorEnvelope} for x in (401, 409)})
def update_profile(
    payload: schemas.UserProfileUpdate,
    user_id: Annotated[str, Depends(get_current_user_id)],):
    """Changes only the profile fields sent.

    `payload.model_dump(exclude_unset=True)` builds the dict of only the
    fields present in the request body — same trick as `PATCH /preferences`.
    That dict is then split in two, even though `country`/`profile_completed`
    now live on the same `user_profiles` (display) table as everything else
    here: the split mirrors the two whitelisted service functions rather
    than a table boundary — `update_profile` accepts one set of columns,
    `update_identity_fields` a narrower, separately-audited set. One HTTP
    call from the client's point of view, two service calls under the hood
    — `services.update_profile` for the general `user_profiles` fields
    (unchanged behavior), then `services.update_identity_fields` for
    `country`/`profile_completed`. `get_profile` is called last so the
    response reflects both writes together, not just whichever ran first.

    Args:
        payload (UserProfileUpdate): Whichever fields the caller sent.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": {...}} — the profile as it now stands.

    Raises:
        UnauthorizedError: No token or an invalid one (401).
        ConflictError: The requested username is already taken (409).

    Examples:
        PATCH /api/v1/users/me  {"display_name": "JF"}
        PATCH /api/v1/users/me  {"country": "CI", "profile_completed": true}
    """
    fields = payload.model_dump(exclude_unset=True)
    identity_fields = {
        key: fields[key] for key in ("country", "profile_completed") if key in fields
    }
    users_fields = {
        key: value for key, value in fields.items() if key not in identity_fields
    }

    services.update_profile(user_id=user_id, fields=users_fields)
    services.update_identity_fields(user_id=user_id, fields=identity_fields)

    row = services.get_profile(user_id=user_id)
    return envelope_(data=row)


@router.post("/me/whatsapp/attach",
             response_model=Envelope[whatsapp_schemas.StartWhatsappSignupResponse],
             responses={x: {"model": ErrorEnvelope} for x in (401, 429)})
def start_whatsapp_attach(
    request: Request,
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    """Generates a code that links a WhatsApp number to the caller's own,
    already-authenticated account.

    Lives here rather than in `app/api/v1/whatsapp_auth.py`: it modifies
    the caller's own account, the same reasoning `PATCH /users/me` is
    already grouped under this router for. The frontend then polls
    `GET /auth/whatsapp/status` with the returned code exactly as it does
    for signup — the confirmation happens on that shared public endpoint,
    since by the time the code is texted in, WAHA has no idea (and does
    not need to know) which endpoint originally issued it.

    Args:
        request (Request): Used to build the rate-limit key.
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: {"data": {"code": ..., "whatsapp_number": ...,
            "expires_in_seconds": ...}}.

    Raises:
        UnauthorizedError: No token, or an invalid one (401).
        RateLimitError: Too many codes started from this IP (429).

    Examples:
        POST /api/v1/users/me/whatsapp/attach   with  Authorization: Bearer <token>
    """
    return envelope_(data=whatsapp_services.start_whatsapp_attach(user_id, request))
