"""Login — the only auth flow built so far. Email/password only; WhatsApp OTP
and Google OAuth are separate, later flows (real app treats them as
independent branches, not variations of this one).
"""

from fastapi import Request

from app.core.config import get_settings
from app.core.db.database import query
from app.core.errors import ConflictError, ErrorCode, UnauthorizedError
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key
from app.core.security.deps.email_verify import (
    consume_email_verify_token,
    generate_email_verify_token,
    store_email_verify_token,
)
from app.core.security.deps.jwt import _decode, create_access_token, create_refresh_token
from app.core.security.deps.password_reset import (
    consume_password_reset_token,
    generate_password_reset_token,
    store_password_reset_token,
)
from app.core.security.deps.passwords import hash_password, verify_password_match
from app.core.security.deps.rate_limit import check_rate_limit
from app.core.security.deps.token_denylist import revoke_token
from app.core.security.deps.user import user_ip
from app.schemas.jwt import TokenAudience
from app.services.email_sender import send_password_reset_email, send_verification_email

LOGIN_MAX_ATTEMPTS = 5
LOGIN_WINDOW_SECONDS = 60

SIGNUP_MAX_ATTEMPTS = 5
SIGNUP_WINDOW_SECONDS = 60

REFRESH_MAX_ATTEMPTS = 10
REFRESH_WINDOW_SECONDS = 60

RESEND_VERIFICATION_MAX_ATTEMPTS = 3
RESEND_VERIFICATION_WINDOW_SECONDS = 300

PASSWORD_RESET_MAX_ATTEMPTS = 3
PASSWORD_RESET_WINDOW_SECONDS = 300


def login(email: str, password: str) -> dict:
    """Verifies email/password, returns a fresh access + refresh token pair.

        Rate-limited by email: an attacker guessing an unknown account's
        password has no id to rate-limit by, only the email they're trying —
        same reasoning as the real API.

        Args:
            email (str): The account's email.
            password (str): The plain-text password to check.

        Returns:
            dict: access_token, refresh_token, token_type.

        Raises:
            RateLimitError: Too many attempts for this email within the
                window (429).
            UnauthorizedError: Wrong password, unknown email, or email not
            verified — `verify_password_match` doesn't distinguish these,
            deliberately, to avoid telling an attacker which half was wrong.
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.LOGIN, email),
        LOGIN_MAX_ATTEMPTS, LOGIN_WINDOW_SECONDS,
        "too many login attempts, try again later",
    )

    verify_password_match(password, email)

    user_id = _get_user_id_by_email(email)

    return {
        "access_token": create_access_token(user_id),
        "refresh_token": create_refresh_token(user_id),
        "token_type": "bearer",
    }


def logout(refresh_token: str, request: Request) -> None:
    """Revokes a refresh token so it can never be exchanged again.

    Verifies the token first (signature, expiry, audience) via _decode —
    same as any other use of a refresh token — then revokes it. An already
    expired or forged token has nothing to revoke, and _decode already
    raises for those cases, so this never revokes garbage.

    Args:
        refresh_token (str): The refresh token being logged out, Bearer
            prefix already stripped.
        request (Request): Needed by _decode for its own logging on failure.

    Raises:
        UnauthorizedError: Expired, forged, or an access token presented
            here instead of a refresh token (wrong audience).
    """
    payload = _decode(refresh_token, TokenAudience.REFRESH, request)
    revoke_token(payload)


def refresh_access_token(refresh_token: str, request: Request) -> dict:
    """Exchanges a valid refresh token for a fresh access token.

        No rotation: the same refresh token keeps working until it naturally
        expires (31 days). Real API deliberately makes the same choice — see
        the reasoning in the real `refresh/route.ts` — rotating would require
        reliably revoking the old one, which we can't do yet (task #37).

        Rate-limited by IP: unlike login, there's no email here to key on
        before the token is even verified.

        Args:
            refresh_token (str): The refresh token, `Bearer ` already stripped.
            request (Request): Needed by `_decode` for its own logging on
                failure, and here to build the rate-limit key.

        Returns:
            dict: access_token, token_type. No new refresh_token — same one.

        Raises:
            RateLimitError: Too many attempts from this IP (429).
            UnauthorizedError: Expired, forged, or an access token presented
                here instead of a refresh token (wrong audience).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.REFRESH, user_ip(request)),
        REFRESH_MAX_ATTEMPTS, REFRESH_WINDOW_SECONDS,
        "too many refresh attempts, try again later",
    )

    user_id = _decode(refresh_token, TokenAudience.REFRESH, request).userId

    return {
        "access_token": create_access_token(user_id),
        "token_type": "bearer",
    }


def signup(email: str, password: str, request: Request) -> dict:
    """Creates an account, then sends the verification email.

    No auto-login — matches the real API, which returns just the created
    id/email, nothing a client could use as a session: verifying the email
    is a separate step (`verify_email`), and login itself already refuses
    an unverified account.

    Sending the email is best-effort: `send_verification_email` never
    raises, only returns False on failure — a broken mail server must not
    turn account creation into a 500. The user can always ask for the link
    to be resent (`resend_verification`).

    Rate-limited by IP, same as the real API's signup route: stops one
    machine from mass-registering accounts, regardless of which email it
    tries next.

    Args:
        email (str): The new account's email. Checked for uniqueness first.
        password (str): Validated by `HardPassword` at the schema layer
            before this ever runs.
        request (Request): Used to build the rate-limit key.

    Returns:
        dict: id, email — the row the database wrote.

    Raises:
        RateLimitError: Too many signups from this IP (429).
        ConflictError: The email is already registered (409).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.SIGNUP, user_ip(request)),
        SIGNUP_MAX_ATTEMPTS, SIGNUP_WINDOW_SECONDS,
        "too many signup attempts, try again later",
    )

    if _email_taken(email):
        raise ConflictError(f"email {email!r} is already registered")

    sql = """
        INSERT INTO users (email, password_hash)
        VALUES (%s, %s)
        RETURNING id, email
        """
    # password is already HardPassword-validated by SignupRequest before it gets here
    rows = query(sql, (email, hash_password(password)))
    row = dict(rows[0])

    _send_verification(str(row["id"]), row["email"])

    return row


def resend_verification(email: str, request: Request) -> None:
    """Sends a fresh verification email — the exact same function signup
    already calls, just triggered on demand instead of automatically.

    Silent on an unknown email: telling a caller "no account with that
    email" lets them enumerate which addresses are registered. Same
    reasoning as `verify_password_match`'s deliberately vague failures.

    Rate-limited by email, separately from signup: without this, anyone
    could spam a stranger's inbox by hammering resend for an email they
    don't own.

    Args:
        email (str): The account to resend a verification link to.
        request (Request): Unused by the logic itself, kept for a
            consistent signature with the other rate-limited functions.

    Raises:
        RateLimitError: Too many resend attempts for this email (429).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.RESEND_VERIFICATION, email),
        RESEND_VERIFICATION_MAX_ATTEMPTS, RESEND_VERIFICATION_WINDOW_SECONDS,
        "too many resend attempts, try again later",
    )

    sql = "SELECT id FROM users WHERE email = %s"
    rows = query(sql, (email,))

    if not rows:
        return

    _send_verification(str(rows[0]["id"]), email)


def verify_email(token: str) -> bool:
    """Consumes a verification token and flips the account to verified.

    Args:
        token (str): From the clicked link's `?token=` query param.

    Returns:
        bool: True if the token was valid and the account is now verified,
            False if the token was unknown, already used, or expired —
            those three cases are indistinguishable on purpose.
    """
    user_id = consume_email_verify_token(token)

    if user_id is None:
        return False

    query(
        "UPDATE users SET email_verified = true WHERE id = %s",
        (user_id,),
        nothing_return=True,
    )
    return True


def request_password_reset(email: str, request: Request) -> None:
    """Sends a password-reset link, if this email belongs to an account.

    Silent on an unknown email: telling a caller "no account with that
    email" lets them enumerate which addresses are registered. Exact same
    reasoning as `resend_verification`, and the same shape — look the email
    up, and just return if there's no row, instead of raising.

    Rate-limited by email, for the same reason `resend_verification` is:
    without this, anyone could spam a stranger's inbox by hammering this
    endpoint for an email they don't own.

    Args:
        email (str): The account whose password is being reset.
        request (Request): Unused by the logic itself, kept for a
            consistent signature with the other rate-limited functions.

    Raises:
        RateLimitError: Too many reset requests for this email (429).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.PASSWORD_RESET, email),
        PASSWORD_RESET_MAX_ATTEMPTS, PASSWORD_RESET_WINDOW_SECONDS,
        "too many password reset attempts, try again later",
    )

    sql = "SELECT id FROM users WHERE email = %s"
    rows = query(sql, (email,))

    if not rows:
        return

    user_id = str(rows[0]["id"])

    token = generate_password_reset_token()
    store_password_reset_token(token, user_id)

    reset_url = f"{get_settings().api_base_url}/reset-password?token={token}"
    send_password_reset_email(email, reset_url)


def reset_password(token: str, new_password: str) -> None:
    """Consumes a password-reset token and sets the account's new password.

    Unlike `verify_email`, which returns a bare bool for an invalid token,
    this raises. Verifying an email is a read-shaped check a client can
    retry harmlessly; resetting a password is a security-sensitive state
    change, and a caller that reaches this with a bad token deserves a real
    error to react to, not a silently-ignored False.

    No rate limiting on the token itself: same reasoning as email
    verification's consume step — the token is 32 random bytes, hex-encoded,
    which is already unguessable enough that the only realistic use of this
    function is with a token copied straight out of the email.

    Args:
        token (str): From the reset-password request body.
        new_password (str): Already `HardPassword`-validated by
            `PasswordResetConfirm` before this ever runs.

    Raises:
        UnauthorizedError: The token is unknown, already used, or expired
            — those three cases are indistinguishable on purpose.
    """
    user_id = consume_password_reset_token(token)

    if user_id is None:
        raise UnauthorizedError(
            "this password reset link is invalid or has expired",
            code=ErrorCode.INVALID_TOKEN,
        )

    query(
        "UPDATE users SET password_hash = %s WHERE id = %s",
        (hash_password(new_password), user_id),
        nothing_return=True,
    )


def _send_verification(user_id: str, email: str) -> None:
    """Generates a token, stores it, and mails the verification link.

    Shared by `signup` (automatic, once) and `resend_verification`
    (on demand) — identical work either way, only the caller differs.
    """
    token = generate_email_verify_token()
    store_email_verify_token(token, user_id)

    verify_url = f"{get_settings().api_base_url}/api/v1/auth/verify-email?token={token}"
    send_verification_email(email, verify_url)


def _email_taken(email: str) -> bool:
    """Whether an account already exists for this email."""
    sql = "SELECT EXISTS (SELECT 1 FROM users WHERE email = %s)"
    rows = query(sql, (email,))

    return rows[0]["exists"]


def _get_user_id_by_email(email: str) -> str:
    """The account id for an email already known to exist and be verified.

    Called only after `verify_password_match` succeeds, so the row is
    guaranteed to be there — this never needs its own not-found handling.
    """
    sql = "SELECT id FROM users WHERE email = %s"
    rows = query(sql, (email,))


    return str(rows[0]["id"])
