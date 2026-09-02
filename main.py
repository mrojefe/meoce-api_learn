"""MEOCE API — entry point."""
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.v1.router import router as v1_router
from app.core.config import get_settings
from app.core.db.database import close_pool, open_pool
from app.core.errors import register_error_handler

settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Opens the connection pool before the first request, closes it after the last.

    Everything before `yield` runs once at startup, everything after runs once
    at shutdown, and the application runs at the `yield`. Opening the pool here
    rather than at import means a failure to reach the database stops the
    application from starting, loudly, instead of surfacing as a 500 on the
    first request.

    Args:
        app (FastAPI): The application being started. Required by the
            signature FastAPI expects, unused here.
    """
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
