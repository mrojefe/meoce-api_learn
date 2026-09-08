"""Auth routes — HTTP only. The work happens in the service."""

from fastapi import APIRouter, Request

from app.schemas import auth as schemas
from app.schemas.common import Envelope, ErrorEnvelope
from app.services import auth as services
from app.services import google_auth as google_services

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", status_code=201,
             response_model=Envelope[schemas.SignupResponse],
             responses={409: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope}})
def signup(body: schemas.SignupRequest, request: Request):
    """Creates an account. No auto-login — see `signup()`'s docstring.

    Args:
        body (SignupRequest): email, password.
        request (Request): Used to rate-limit by IP.

    Returns:
        dict: {"data": {id, email}} with 201 Created.

    Raises:
        RateLimitError: Too many signups from this IP (429).
        ConflictError: The email is already registered (409).

    Examples:
        POST /api/v1/auth/signup  {"email": "jf@example.com", "password": "..."}
    """
    return {"data": services.signup(body.email, body.password, request)}


@router.post("/login", response_model=Envelope[schemas.TokenPair],
             responses={401: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope}})
def login(body: schemas.LoginRequest):
    """Verifies email/password, returns a fresh access + refresh token pair.

        Args:
            body (LoginRequest): email, password.

        Returns:
            dict: {"data": {access_token, refresh_token, token_type}}.

        Raises:
            RateLimitError: Too many attempts for this email (429).
            UnauthorizedError: Wrong password or unknown email (401) — same
                error either way, deliberately, so a failed guess doesn't reveal
                which half was wrong.

        Examples:
        POST /api/v1/auth/login  {"email": "jf@example.com", "password": "..."}
    """
    return {"data": services.login(body.email, body.password)}


@router.post("/logout", status_code=204,
             responses={401: {"model": ErrorEnvelope}})
def logout(body: schemas.LogoutRequest, request: Request):
    """Revokes a refresh token — this one device only.

        Args:
            body (LogoutRequest): refresh_token.
            request (Request): Passed through so _decode can log the caller's
                IP on a failed attempt.

        Raises:
            UnauthorizedError: Expired, forged, or an access token presented
                here instead of a refresh token (401).

        Examples:
        POST /api/v1/auth/logout  {"refresh_token": "..."}
    """
    services.logout(body.refresh_token, request)


@router.post("/refresh", response_model=Envelope[schemas.AccessToken],
             responses={401: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope}})
def refresh(body: schemas.RefreshRequest, request: Request):
    """Exchanges a valid refresh token for a fresh access token.

        Args:
            body (RefreshRequest): refresh_token.
            request (Request): Passed through so `_decode` can log the caller's
                IP on a failed attempt.

        Returns:
            dict: {"data": {access_token, token_type}}. No new refresh_token —
                the real API doesn't rotate it, neither do we (see task #37).

        Raises:
            UnauthorizedError: Expired, forged, or an access token presented
                here instead of a refresh token (401).

        Examples:
        POST /api/v1/auth/refresh  {"refresh_token": "..."}
    """
    return {"data": services.refresh_access_token(body.refresh_token, request)}


@router.post("/resend-verification", status_code=204,
             responses={429: {"model": ErrorEnvelope}})
def resend_verification(body: schemas.ResendVerificationRequest, request: Request):
    """Sends a fresh verification email.

        Always 204, even for an unknown email — see `resend_verification()`'s
        docstring: revealing "no account with that email" would let a caller
        enumerate registered addresses.

        Args:
            body (ResendVerificationRequest): email.
            request (Request): Unused by the logic, kept for a consistent
                signature with the other rate-limited routes.

        Raises:
            RateLimitError: Too many resend attempts for this email (429).

        Examples:
        POST /api/v1/auth/resend-verification  {"email": "jf@example.com"}
    """
    services.resend_verification(body.email, request)


@router.get("/verify-email", response_model=Envelope[bool])
def verify_email(token: str):
    """Consumes a verification token — the link a user clicks in their email.

        GET, not POST: clicked from a plain `<a href>` in an email, which can
        never carry a body.

        Args:
            token (str): From the link's `?token=` query param.

        Returns:
            dict: {"data": true} if the account is now verified, {"data":
                false} if the token was unknown, already used, or expired
                — those three cases are indistinguishable on purpose.

        Examples:
        GET /api/v1/auth/verify-email?token=abc123...
    """
    return {"data": services.verify_email(token)}


@router.post("/request-password-reset", status_code=204,
             responses={429: {"model": ErrorEnvelope}})
def request_password_reset(body: schemas.PasswordResetRequest, request: Request):
    """Sends a password-reset link.

        Always 204, even for an unknown email — same enumeration-prevention
        reasoning as `resend_verification`'s docstring: revealing "no account
        with that email" would let a caller find out which addresses are
        registered.

        Args:
            body (PasswordResetRequest): email.
            request (Request): Unused by the logic, kept for a consistent
                signature with the other rate-limited routes.

        Raises:
            RateLimitError: Too many reset requests for this email (429).

        Examples:
        POST /api/v1/auth/request-password-reset  {"email": "jf@example.com"}
    """
    services.request_password_reset(body.email, request)


@router.post("/reset-password", status_code=204,
             responses={401: {"model": ErrorEnvelope}})
def reset_password(body: schemas.PasswordResetConfirm):
    """Consumes a password-reset token and sets a new password.

        No rate limiting here on the token itself: the token is 32 random
        bytes, hex-encoded — the same unguessability that already lets
        `verify-email`'s consume step skip a rate limit is the security
        control on this route too, not a request counter.

        Args:
            body (PasswordResetConfirm): token, new_password.

        Raises:
            UnauthorizedError: The token is unknown, already used, or
                expired (401) — those three cases are indistinguishable on
                purpose.

        Examples:
        POST /api/v1/auth/reset-password  {"token": "...", "new_password": "..."}
    """
    services.reset_password(body.token, body.new_password)


@router.post("/google", response_model=Envelope[schemas.TokenPair],
             responses={401: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope}})
def google_sign_in(body: schemas.GoogleAuthRequest, request: Request):
    """Verifies a Google ID token, returns a fresh access + refresh pair.

        Creates the account on a first sign-in, links onto a matching
        password/WhatsApp account by email, or logs a returning Google user
        in — see `google_sign_in()`'s docstring for the full linking policy.

        Args:
            body (GoogleAuthRequest): id_token.
            request (Request): Used to rate-limit by IP.

        Returns:
            dict: {"data": {access_token, refresh_token, token_type}}.

        Raises:
            RateLimitError: Too many attempts from this IP (429).
            UnauthorizedError: The token is invalid/expired, or Google
                reports the email as unverified (401).

        Examples:
        POST /api/v1/auth/google  {"id_token": "..."}
    """
    return {"data": google_services.google_sign_in(body.id_token, request)}
