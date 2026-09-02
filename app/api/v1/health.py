"""Liveness probe - see model 01 """

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.config import get_settings
from app.core.security.deps import get_current_user_id
from app.schemas.common import HealthResponse

router = APIRouter(tags=["health"])

@router.get("/health", response_model = HealthResponse)
def health():
    """Liveness probe — and which database this instance is pointing at.

    Reports the environment and the database host so that "am I on staging or
    production?" is answerable with one curl. Two identical Supabase stacks run
    on the same machine, distinguished only by a UUID.

    The password and user are deliberately absent: HealthResponse declares
    exactly five fields, so nothing else can leave through this endpoint.

    Returns:
        dict: status, version, env, db_host, db_port.

    Examples:
        >>> # GET /api/v1/health
        {'status': 'ok', 'version': '0.2.0', 'env': 'dev',
         'db_host': '127.0.0.1', 'db_port': 5433}
    """
    settings = get_settings()
    return_health = {
        "status" : "ok",
        "version" : settings.api_version,
        "env": settings.env,
        "db_host" : settings.postgres_host,
        "db_port" : settings.postgres_port
    }
    return return_health



@router.get("/whoami")
def whoami(user_id: Annotated[str ,Depends(get_current_user_id)]):
    """Returns the id of whoever is calling. A test bench for authentication.

    Deliberately does nothing else, so that a failure here is unambiguously an
    authentication failure rather than anything to do with the database.

    Four cases worth checking after any change to the auth path:

    * a valid access token  -> 200 with the user id
    * no Authorization header -> 401
    * a malformed token     -> 401 `invalid_token`
    * a *refresh* token     -> 401, refused by the `aud` claim

    Returns:
        dict: {"user_id": "..."} — not wrapped in the envelope, since this is a
            diagnostic endpoint rather than part of the public contract.
    """
    return {"user_id": user_id}