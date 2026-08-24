"""Liveness probe - see model 01 """

from fastapi import APIRouter
from app.core.config  import get_settings
from app.schemas.common import HealthResponse

router = APIRouter(tags=["health"])

@router.get("/health", response_model = HealthResponse)
def health():
    settings = get_settings()
    return_health = {
        "status" : "ok",
        "version" : settings.api_version,
        "env": settings.env,
        "db_host" : settings.postgres_host,
        "db_port" : settings.postgres_port
    }
    return return_health