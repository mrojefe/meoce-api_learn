"""MEOCE API — entry point."""
from fastapi import FastAPI

from app.api.v1.router import router as v1_router
from contextlib import asynccontextmanager
from app.core.errors import register_error_handler
from app.core.config  import get_settings 
from app.core.database import open_pool, close_pool

settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI):
    open_pool()          # before the first request
    yield                # the app runs
    close_pool()         # after the last one


app = FastAPI(
    title="MEOCE API",
    description="The MEOCE API, rebuilt by hand.",
    version=settings.api_version,
    lifespan=lifespan,
    docs_url="/docs" if settings.env == "dev" else None,
    redoc_url="/redoc" if settings.env == "dev" else None,
)

register_error_handler(app)
app.include_router(v1_router)
