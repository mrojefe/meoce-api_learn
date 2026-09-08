"""Token mechanics — creating and verifying a JWT. Nothing about who the
caller is beyond the raw claim; that belongs to `user.py`.
"""

import logging
import secrets
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Request
from pydantic import ValidationError

from app.core.config import get_settings
from app.core.errors import ErrorCode, UnauthorizedError
from app.core.security.deps.token_denylist import assert_token_not_revoked
from app.schemas.jwt import JwtParams, TokenAudience, TokenClaims

settings = get_settings()
logger = logging.getLogger("meoce.security")

ACCESS_TOKEN_EXPIRATION = timedelta(minutes=30)
REFRESH_TOKEN_EXPIRATION = timedelta(days=31)




def _create_token(user_id: str, aud: TokenAudience, expires_in: timedelta) -> str:
    """Signs a new JWT carrying `userId`, scoped to `aud`, valid for `expires_in`.

    Shared by `create_access_token` and `create_refresh_token` — the only
    difference between the two is which audience and how long they live.
    """
    now = datetime.now(UTC)
    exp = int((now + expires_in).timestamp()) #json don't know about type datatime
    jti = secrets.token_hex(32)
    claims = TokenClaims(
        jti = jti,
        userId=user_id,
        iat=int(now.timestamp()),
        exp=exp,
        aud=aud,
        iss=JwtParams.ISSUER,
    )

    real_jwt_secret = settings.jwt_secret.get_secret_value()

    return jwt.encode(
        payload=claims.model_dump(),# payload takes a dict 
        key=real_jwt_secret,
        algorithm=JwtParams.ALGORITHM,
    )

# add in create_* stuff to verify the user status if it other than actif  
# raise situation but don't create 
#  
def create_access_token(user_id: str) -> str:
    """Mints a 30-minute access token — what a route checks on every request."""
    return _create_token(user_id, TokenAudience.ACCESS, ACCESS_TOKEN_EXPIRATION)


def create_refresh_token(user_id: str) -> str:
    """Mints a 31-day refresh token — exchanged for a new access token only."""
    return _create_token(user_id, TokenAudience.REFRESH, REFRESH_TOKEN_EXPIRATION)


def _claimed_user_id(token: str) -> str:
    """Reads the userId a token CLAIMS, verifying nothing.

    For logs only. The signature has already failed by the time this runs, so
    the value is an assertion by whoever built the token, never an identity.
    Returns "?" rather than raising: logging must not turn a 401 into a 500.
    """
    try:
        payload = jwt.decode(token, options={"verify_signature": False})
        return str(payload.get("userId", "?"))
    except Exception:  # noqa: BLE001 — logging must never be what breaks
        return "?"


def _decode(token: str,aud: TokenAudience , request: Request) -> str:
    # NOTE: the leading underscore means "not exported via __init__.py", but
    # user.py (a sibling file in this same package) still imports it directly
    # — a real smell, left as-is for now. Rename to `decode` (still excluded
    # from __init__.py's public re-exports) if this bothers you later.
    """Verifies a token and returns the user id it carries.

        Private on purpose. The two public dependencies decide the *policy* —
        whether a route requires a user or merely tolerates one — while this
        decides only whether a token is genuine. A route importing it directly
        would bypass that decision, and would also hand it the raw header,
        `Bearer ` prefix included, which the JWT library would reject as malformed.

        Six checks happen inside one `jwt.decode` call, and any of them failing
        raises:

        * the signature is recomputed with our secret and compared — proof the
        token was minted by us and not altered since
        * `exp` against the clock, and `require: ["exp"]` so that a token with no
        expiry is refused rather than treated as eternal
        * `aud` — this is what refuses the 30-day *refresh* token when it is
        presented as an access token
        * `iss` — refuses a token issued by some other system of ours

        `algorithms=["HS256"]` is not optional. Left out, some libraries trust the
        algorithm the token itself declares, and a token can declare `"alg":
        "none"` — meaning "no signature, take my word for it".

        What this cannot know: whether the user logged out a minute ago, or was
        banned since. A signature is a fact about when the token was minted; those
        are facts about now, and need a lookup (see the note at the end).

        Args:
            token (str): The token alone, with `Bearer ` already stripped.

        Returns:
            str: The `userId` claim.

        Raises:
            UnauthorizedError: Expired (401, `token_expired`), invalid or forged
                (401, `invalid_token`), or valid but carrying no userId.
        """

    real_jwt_secret = settings.jwt_secret.get_secret_value()

    try:
        payload = jwt.decode(
                jwt=token,
                key=real_jwt_secret,
                algorithms=[JwtParams.ALGORITHM],
                options={"require": [JwtParams.REQUIRE]}, #refuse token with no expiration
                audience=aud,
                issuer=JwtParams.ISSUER,
        )
        payload = TokenClaims(**payload) # pydantic validation
    except ValidationError:

        raise UnauthorizedError("Your token aren't valide",ErrorCode.INVALID_TOKEN, )

    except jwt.ExpiredSignatureError:
        raise UnauthorizedError("Your session has expired, please log back in",ErrorCode.TOKEN_EXPIRED, )
    except jwt.InvalidTokenError as exc:
        # The only failure here that cannot happen by accident. An expired
        # token is ordinary — everyone's expires. A signature that does not
        # match means someone built the token deliberately, so it is the one
        # line in this file worth a WARNING.
        #
        # `claimed` is what the token SAYS, never who the caller is: the
        # signature failed, so nothing inside it is trustworthy. It is logged
        # only because a repeated value points at whose account is targeted.
        # Imported here, not at the top of the file: user.py already imports
        # _decode FROM this module, so importing user_ip back at module level
        # would be a circular import. By the time this line actually runs,
        # both modules have finished loading, so the deferred import is safe.
        from app.core.security.deps.user import user_ip

        logger.warning(
            "invalid token from %s — %s — claimed userId %s",
            user_ip(request), type(exc).__name__, _claimed_user_id(token),
        )
        raise UnauthorizedError("Invalid token", ErrorCode.INVALID_TOKEN) from exc

    if not payload.userId:
        raise UnauthorizedError("Token carries no userId",ErrorCode.INVALID_TOKEN,)

    assert_token_not_revoked(payload) #Raises if this token's jti was revoked

    # NOTE — two checks the real API adds here, still deliberately left out:
    # account status (banned or suspended?) and publishing the actor for the
    # audit trail. Each answers a question the signature cannot: the
    # signature is a fact about when the token was minted, those are facts
    # about now. Added one at a time, once this base is solid.
    return payload
