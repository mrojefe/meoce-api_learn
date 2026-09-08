"""Password reset tokens — random, single-use, stored in Redis.

Same shape as `email_verify.py`, deliberately: it's not a JWT either — this
token proves nothing about *who* holds it, only that whoever has it was
handed the reset link. Redis is the only place that knows which user it
belongs to, which is why it's looked up (and immediately deleted) by key,
not decoded.
"""

import secrets
from datetime import timedelta

from app.core.db.redis import get_redis
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key

PASSWORD_RESET_TTL_HOURS = 1


def generate_password_reset_token() -> str:
    """A random, unguessable token — 32 bytes, hex-encoded.

    Returns:
        str: 64 hex characters. Not a JWT — there's nothing to decode,
            only to look up.
    """
    return secrets.token_hex(32)


def store_password_reset_token(token: str, user_id: str) -> None:
    """Remembers which user a token belongs to, for 1 hour.

    Same TTL choice as email verification: short enough that a leaked or
    forwarded link stops being useful quickly, long enough that a real user
    has time to open their inbox and click it.

    Args:
        token (str): From `generate_password_reset_token`.
        user_id (str): The account this token will let its holder reset the
            password of, once consumed.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.PASSWORD_RESET, token)
    get_redis().set(key, user_id, ex=timedelta(hours=PASSWORD_RESET_TTL_HOURS))


def consume_password_reset_token(token: str) -> str | None:
    """Looks up and immediately deletes a token — single use.

    Deleting on read (not just on success) matters here even more than for
    email verification: a password-reset token that could be replayed would
    let anyone who once intercepted a link keep resetting the password
    indefinitely.

    Args:
        token (str): The token submitted in the reset-password request body.

    Returns:
        str | None: The user id it belonged to, or None if the token is
            unknown, already used, or expired — those three cases are
            indistinguishable on purpose, same reasoning as
            `verify_password_match` not revealing which half was wrong.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.PASSWORD_RESET, token)
    r = get_redis()

    user_id = r.get(key)
    r.delete(key)

    return user_id
