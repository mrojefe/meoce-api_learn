"""Machine-to-machine auth — the shared X-API-KEY header.

An API key answers "are you a trusted machine?" — it is one shared secret,
held by Airflow and by this API, with no human to log in and nothing to
expire. Answering "*which person* is calling?" is a different question and
lives in `user.py`.
"""

import hmac
from typing import Annotated

from fastapi import Depends
from fastapi.security import APIKeyHeader

from app.core.config import get_settings
from app.core.errors import ErrorCode, UnauthorizedError

settings = get_settings()

api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)
"""
    Reads the X-API-KEY header, and declares it to OpenAPI as a *credential*.

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
