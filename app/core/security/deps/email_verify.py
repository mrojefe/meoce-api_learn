"""Email verification tokens — random, single-use, stored in Redis.

Not a JWT: this token proves nothing about *who* holds it, only that
whoever clicked the link had it — Redis is the only place that knows which
user it belongs to. That's why it's looked up (and immediately deleted) by
key, not decoded like a JWT.
"""

import secrets
from datetime import timedelta

from app.core.db.redis import get_redis
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key

EMAIL_VERIFY_TTL_HOURS = 1



def generate_email_verify_token() -> str:
    """A random, unguessable token — 32 bytes, hex-encoded.

    Returns:
        str: 64 hex characters. Not a JWT — there's nothing to decode,
            only to look up.
    """
    return secrets.token_hex(32)


def store_email_verify_token(token: str, user_id: str) -> None:
    """Remembers which user a token belongs to, for 24 hours.

    Args:
        token (str): From `generate_email_verify_token`.
        user_id (str): The account this token will verify, once consumed.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.VERIFICATION,token)
    get_redis().set(key, user_id, ex=timedelta(hours=EMAIL_VERIFY_TTL_HOURS))


def consume_email_verify_token(token: str) -> str | None:
    """Looks up and immediately deletes a token — single use.

    Deleting on read (not just on success) matters: a token that gets used
    once should never verify a second account, even if this is called again
    with the same value by mistake or by someone replaying the link.

    Args:
        token (str): The token from the clicked link's `?token=` query param.

    Returns:
        str | None: The user id it belonged to, or None if the token is
            unknown, already used, or expired — those three cases are
            indistinguishable on purpose, same reasoning as
            `verify_password_match` not revealing which half was wrong.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.VERIFICATION,token)
    r = get_redis()

    user_id = r.get(key)
    r.delete(key)

    return user_id
