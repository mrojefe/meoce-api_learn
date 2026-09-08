"""WhatsApp signup routes — HTTP only, thin, same shape as `auth.py`'s
`/google` route. Both public: `start` needs no identity yet (that's the
whole point of signing up), and `status`'s "secret" is the 6-digit code
itself — same trust model already applied to an email-verify token, see
`whatsapp_code.py`'s module docstring.

The authenticated *attach* route (`POST /users/me/whatsapp/attach`) is
deliberately NOT here — it lives in `app/api/v1/user_profile.py`, under the
`/users` router, because it modifies the caller's own account, the same
reasoning `PATCH /users/me` is already grouped there.
"""

from fastapi import APIRouter, Request

from app.schemas import whatsapp_auth as schemas
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
from app.services import whatsapp_auth as services

router = APIRouter(prefix="/auth/whatsapp", tags=["auth"])


@router.post("/start", response_model=Envelope[schemas.StartWhatsappSignupResponse],
             responses={429: {"model": ErrorEnvelope}})
def start_whatsapp_signup(request: Request):
    """Generates a code for a new signup and returns what to show the user.

    Args:
        request (Request): Used to build the rate-limit key.

    Returns:
        dict: {"data": {"code": ..., "whatsapp_number": ...,
            "expires_in_seconds": ...}}.

    Raises:
        RateLimitError: Too many codes started from this IP (429).

    Examples:
        POST /api/v1/auth/whatsapp/start
    """
    return envelope_(data=services.start_whatsapp_signup(request))


@router.get("/status", response_model=Envelope[schemas.WhatsappStatusResponse],
            responses={429: {"model": ErrorEnvelope}})
def whatsapp_status(code: str):
    """Polled by the frontend to learn whether the code has been confirmed.

    A "pending" status is the ordinary, expected response while the user
    hasn't texted the code yet — not an error the frontend needs to
    surface, just "keep polling."

    Args:
        code (str): The 6-digit code from `start_whatsapp_signup`.

    Returns:
        dict: {"data": {"status": "pending"}} or {"data": {"status":
            "confirmed", "access_token": ..., "refresh_token": ...,
            "token_type": ...}}.

    Raises:
        RateLimitError: Too many status checks for this code (429).

    Examples:
        GET /api/v1/auth/whatsapp/status?code=123456
    """
    return envelope_(data=services.check_whatsapp_status(code))
