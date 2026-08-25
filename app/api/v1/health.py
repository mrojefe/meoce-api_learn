"""Liveness probe - see model 01 """

from fastapi import APIRouter

from app.core.config import get_settings
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