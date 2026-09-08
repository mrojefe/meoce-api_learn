"""Identity and entitlements — who is calling, and what their plan allows.

Answering "*which person* is calling?" needs a JWT, per user, expiring,
revocable — token mechanics live in `jwt.py`, this file turns a verified
token into an identity and, from there, into what that identity is entitled
to.
"""

from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.reference import Feature
from app.core.security.deps.jwt import _decode
from app.schemas.jwt import TokenAudience
from app.schemas.plans import PlanFeatures
from app.services.entitlements import resolve_entitlements

bearer_scheme = HTTPBearer(auto_error=False)


def user_ip(request: Request) -> str:
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


def get_current_user_id(
    request: Request,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],) -> str:
    """Refuses the request unless it carries the  autorization require
        And get the id of the sender
    """

    if not creds :
        raise UnauthorizedError("Authorization: Bearer <token> header required")

    x_jwt_secret = creds.credentials.strip()


    return _decode(x_jwt_secret,TokenAudience.ACCESS, request).userId



def get_current_entitlements(
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> PlanFeatures:
    """
        What the caller's plan allows.

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
        # feature is of type Feature, so below, if the entilements
        # doesn't have this precie feature we overide the ouput by False
        #getattr it's equivalent of .get (dict.get) for pydantic object 
        granted = getattr(entitlements, feature.value, False)
        if not granted:
            raise ForbiddenError(
                f"Your plan does not include {feature.value}",
            )

    return checker
