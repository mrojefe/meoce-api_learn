"""Revoked JWTs — logout, password change, admin lockout all land here.

A JWT can't be un-signed once issued, so "revoking" one means remembering
its jti separately and rejecting it on sight — the same shape as
email_verify, but marking a token dead instead of marking one used.
"""

import time

from app.core.db.redis import get_redis
from app.core.errors import ErrorCode, UnauthorizedError
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key
from app.schemas.jwt import TokenClaims


def revoke_token(payload: TokenClaims) -> None:
    """Marks a token's jti as dead until it would have expired anyway.

    Args:
        payload (TokenClaims): The decoded, already-validated token being
            revoked — its own jti and exp are what we act on.
    """
    ttl = payload.exp - int(time.time())
    if ttl > 0:
        key = valide_rate_limite_key(StartRateLimitKeyTypes.REVOKED_JTI, payload.jti)
        get_redis().set(key, "1", ex=ttl)


def assert_token_not_revoked(payload: TokenClaims) -> None:
    """Raises if this token's jti was revoked — logout, password change, lockout.

    Args:
        payload (TokenClaims): The decoded, already-validated token being
            checked.

    Raises:
        UnauthorizedError: This specific token was revoked, even though its
            signature and expiry are otherwise still valid.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.REVOKED_JTI, payload.jti)
    if get_redis().exists(key):
        raise UnauthorizedError("Token has been revoked", ErrorCode.TOKEN_REVOKED)
