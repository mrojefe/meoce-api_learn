"""MEOCE API — entry point."""
from fastapi import FastAPI

from app.api.v1.router import router as v1_router
from app.core.errors import register_error_handler
from app.core.config  import get_settings 

app = FastAPI(
    title="MEOCE API",
    description="The MEOCE API, rebuilt by hand.",
    version=get_settings().api_version,
)

register_error_handler(app)
app.include_router(v1_router)
