"""Dependencies — the checks that run *before* a route, not inside it.

A dependency is a function FastAPI calls first, whose result it passes to the
route. Two things make that worth doing for security:

* **It cannot be forgotten.** Written inside the route, an auth check is copied
  into every protected endpoint, and the fifteenth copy is the one that drifts.
  Written here, it is declared once and applied by the decorator.
* **A raise stops the route.** If this file raises, the endpoint body never
  runs — the route is unreachable without credentials, by construction rather
  than by discipline.

**This file authenticates *systems*, not people.** An API key answers "are you a
trusted machine?" — it is one shared secret, held by Airflow and by this API,
with no human to log in and nothing to expire. Answering "*which person* is
calling?" is a different question, needs a different mechanism (a JWT, per user,
expiring, revocable), and lands in module 10 next to this one.

Both can coexist: a route may require a key, a user, or both.
"""

import hmac
import logging
from typing import Annotated

import jwt
from fastapi import Depends, Request
from fastapi.security import (
    APIKeyHeader,
    HTTPAuthorizationCredentials,
    HTTPBearer,
)

from app.core.config import get_settings
from app.core.errors import ErrorCode, ForbiddenError, UnauthorizedError
from app.core.reference import Feature
from app.schemas.plans import PlanFeatures
from app.services.entitlements import resolve_entitlements

settings = get_settings()

api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)
"""Reads the X-API-KEY header, and declares it to OpenAPI as a *credential*.

A plain `Header(...)` would work identically at runtime and be documented
wrongly: it appears as an ordinary input parameter, marked `required: false`
because it defaults to None — so `/openapi.json` advertises as optional a header
without which every call is a 401, and a generated client would omit it.

`APIKeyHeader` instead emits a `securitySchemes` entry. That is what puts the
padlock on protected routes in `/docs` and the **Authorize** button at the top
of the page, where the key is entered once for the whole session.

`auto_error=False` is deliberate: left at True it raises FastAPI's own 403 with
FastAPI's own message, escaping the error contract of module 05. Refusing here
keeps every failure in the same shape.
"""

def require_api_key(
    x_api_key: Annotated[str | None, Depends(api_key_header)]) -> None:
    """Refuses the request unless it carries the shared API key.

    Attached to a route through `dependencies=[Depends(require_api_key)]` rather
    than as a parameter, because there is nothing useful to hand the route: one
    key, one calling system, no identity to learn. The function exists purely
    for its side effect — raise, or let the request through — which is why it
    returns None.

    Contrast `get_current_user_id` (module 10), which *does* return something:
    the route needs the user id to know whose rows to read.

    Args:
        x_api_key (str | None): The X-API-KEY header, or None when absent.
            Supplied by `api_key_header`.

    Returns:
        None: Silence means the caller is allowed through.

    Raises:
        UnauthorizedError: The header is missing or empty (401), or the key does
            not match (401). The registered handler turns it into the error
            contract; this function knows nothing about HTTP.

    Examples:
        >>> @router.post("", dependencies=[Depends(require_api_key)])
        ... def create_instrument(...): ...
    """
    # Two separate checks, and the order is not cosmetic: compare_digest raises
    # TypeError on None, so "is it there?" must come first. `not x_api_key`
    # rather than `is None` because it also catches an empty header value.
    
    if not x_api_key  :
        raise UnauthorizedError("X-API-KEY header required")

    # compare_digest, never ==. String comparison stops at the first differing
    # character, so a wrong key sharing more leading characters is rejected
    # measurably more slowly. Repeated, that timing difference reveals the key
    # one character at a time — a 32-character secret falls in ~2,000 tries
    # instead of 64**32. compare_digest always takes the same time.
    real_api_key = settings.api_key.get_secret_value()
    same_key = hmac.compare_digest(x_api_key, real_api_key)

    if not same_key :   
        raise UnauthorizedError("X-API-KEY is not valid",
                                ErrorCode.INVALID_TOKEN)


def _client_ip(request: Request) -> str:
    """The caller's IP, honouring the proxy header when there is one.

    Behind Coolify/Traefik the socket address is the proxy, so the real client
    is the first entry of X-Forwarded-For. That header is trusted only because
    our own proxy sets it — exposed directly to the internet, anyone could
    forge it.
    """
    client_ip = "" 
    forwarded = request.headers.get("x-forwarded-for")

    if forwarded:
        client_ip = forwarded.split(",")[0].strip()
    else :
        #no proxy so take directly the ip from the client open socket
        client_ip = request.client.host  if request.client else "unknown"
        
    return client_ip


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


def _decode(token: str, request: Request) -> str:
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
                token, 
                real_jwt_secret,
                algorithms=["HS256"],
                options={"require": ["exp"]}, #refuse token with no expiration
                audience="meoce-app",
                issuer="meoce-api",
        )
        
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
        logger.warning(
            "invalid token from %s — %s — claimed userId %s",
            _client_ip(request), type(exc).__name__, _claimed_user_id(token),
        )
        raise UnauthorizedError("Invalid token", ErrorCode.INVALID_TOKEN) from exc

    user_id = payload.get("userId")

    if not user_id:
        raise UnauthorizedError("Token carries no userId",ErrorCode.INVALID_TOKEN,)

    # NOTE — three checks the real API adds here, deliberately left out for now:
    # revocation (has this token been logged out?), account status (banned or
    # suspended?), and publishing the actor for the audit trail. Each answers a
    # question the signature cannot: the signature is a fact about when the
    # token was minted, those are facts about now. Added one at a time, once
    # this base is solid.
    return user_id

logger = logging.getLogger("meoce.security")

bearer_scheme = HTTPBearer(auto_error=False)

def get_current_user_id(
    request: Request,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],) -> str:
    """Refuses the request unless it carries the  autorization require
        And get the id of the sender
    """

    if not creds :
        raise UnauthorizedError("Authorization: Bearer <token> header required")

    x_jwt_secret = creds.credentials.strip()

    
    return _decode(x_jwt_secret, request)


def get_current_entitlements(
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> PlanFeatures:
    """What the caller's plan allows.

    A dependency that depends on a dependency: FastAPI resolves the chain
    token -> user_id -> plan, and hands the route the finished answer.

    It returns the whole `PlanFeatures` rather than a plan code, because a code
    tells a route nothing — `"pro"` still has to be turned into a number before
    anything can be compared. The route wants `entitlements.max_watchlists`,
    not a string it must look up itself.

    Costs one query per request that uses it. Deliberately not cached yet: a
    short cache is the right answer and belongs in the module that teaches
    caching, not copied in ahead of understanding it.

    Args:
        user_id (str): The authenticated caller, from the token.

    Returns:
        PlanFeatures: Every limit and switch the plan grants. Falls back to the
            free plan when no active subscription is found.

    Examples:
        >>> def create_watchlist(ent: Annotated[PlanFeatures, Depends(get_current_entitlements)]):
        ...     if ent.max_watchlists is not None and count >= ent.max_watchlists:
        ...         raise ForbiddenError(...)
    """
    return resolve_entitlements(user_id)


def require_feature(feature: Feature):
    """Builds a dependency that refuses the route unless the plan grants a switch.

    For all-or-nothing features only — `intraday_granular_timeframes`,
    `pro_chart_types`. A numeric limit cannot use this, because deciding it
    needs to know how many the user already has, and a dependency runs before
    the route has counted anything.

    Note the shape: this is a function that RETURNS a dependency, rather than
    being one. That is what lets it be parameterised at route definition time:

        dependencies=[Depends(require_feature(Feature.PRO_CHART_TYPES))]
                              └─ called now, returns the checker ─┘
                      └─ FastAPI calls THAT per request ─┘

    Written as `Depends(require_feature)` without the call, FastAPI would try to
    inject `feature` as a request parameter and fail.

    403, not 401. The caller is perfectly well identified; their plan simply
    does not include this. A new token would change nothing, which is exactly
    the distinction between the two codes.

    Args:
        feature (Feature): The switch to require. An enum rather than a string,
            so a typo is caught when the module is imported rather than
            producing a route that silently allows everyone.

    Returns:
        A dependency FastAPI will call on each request.

    Raises:
        ForbiddenError: The plan does not grant it (403).

    Examples:
        >>> @router.get("/intraday",
        ...     dependencies=[Depends(require_feature(Feature.INTRADAY_GRANULAR_TIMEFRAMES))])
        ... def intraday(...): ...
    """

    def checker(
        entitlements: Annotated[PlanFeatures, Depends(get_current_entitlements)],
    ) -> None:
        """Refuses the request unless the plan grants `feature`."""
        granted = getattr(entitlements, feature.value, False)
        if not granted:
            raise ForbiddenError(
                f"Your plan does not include {feature.value}",
            )

    return checker
