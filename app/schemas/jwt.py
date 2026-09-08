from enum import StrEnum

from pydantic import BaseModel


class JwtParams(StrEnum):
    """The fixed, non-secret facts about every JWT this API issues.

    The secret used to sign/verify lives in settings (env), read directly in
    jwt.py at the point of use — not here. This holds only format constants:
    plain strings, true for every token regardless of environment.
    """

    ALGORITHM = "HS256"
    REQUIRE = "exp"
    ISSUER = "meoce-api"


class TokenAudience(StrEnum):
    """What a token is FOR — stamped in at creation, checked at verification.

    Scopes a credential to one job: an access token cannot be presented where
    a refresh token belongs, and vice versa, even though both are otherwise
    valid, signed, unexpired JWTs.
    """

    ACCESS = "meoce-app"
    REFRESH = "meoce-refresh"


class TokenClaims(BaseModel):
    """What every JWT this API issues carries — nothing else.

        Creation builds one of these, then `.model_dump()`s it for `jwt.encode`.
        Verification validates `jwt.decode`'s raw dict back into this, so a token
        missing or mistyping a claim fails loudly here instead of downstream.
    """

    jti: str
    userId: str
    iat: int
    exp: int
    aud: TokenAudience
    iss: str
