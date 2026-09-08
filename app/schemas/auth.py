from uuid import UUID

from pydantic import BaseModel, EmailStr

from app.schemas.common import HardPassword


class SignupRequest(BaseModel):
    """The body accepted by POST /auth/signup."""

    email: EmailStr
    password: HardPassword


class SignupResponse(BaseModel):
    """The body returned by POST /auth/signup — the created account, not a
    session. See `signup()`'s docstring for why there's no token here.
    """

    id: UUID
    email: EmailStr


class LoginRequest(BaseModel):
    """The body accepted by POST /auth/login. Plain `str` password, not
    `HardPassword` — an existing account's password must still verify even
    if it predates the current password policy.
    """

    email: EmailStr
    password: str


class TokenPair(BaseModel):
    """The body returned by POST /auth/login."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    """The body accepted by POST /auth/refresh."""

    refresh_token: str


class LogoutRequest(BaseModel):
    """The body accepted by POST /auth/logout."""

    refresh_token: str


class AccessToken(BaseModel):
    """The body returned by POST /auth/refresh — no refresh_token: no
    rotation, the caller already has the one that still works.
    """

    access_token: str
    token_type: str = "bearer"


class ResendVerificationRequest(BaseModel):
    """The body accepted by POST /auth/resend-verification."""

    email: EmailStr


class PasswordResetRequest(BaseModel):
    """The body accepted by POST /auth/request-password-reset."""

    email: EmailStr


class PasswordResetConfirm(BaseModel):
    """The body accepted by POST /auth/reset-password.

    `new_password` is `HardPassword`, not plain `str` — unlike `LoginRequest`,
    there's no existing-account-predates-the-policy concern here: this is
    the password being *set*, so it must meet the current policy.
    """

    token: str
    new_password: HardPassword


class GoogleAuthRequest(BaseModel):
    """The body accepted by POST /auth/google.

    Just the ID token — `google_sign_in` decodes everything else (email,
    verified-ness, name, avatar) straight out of it once Google's own
    verification confirms it hasn't been tampered with.
    """

    id_token: str
