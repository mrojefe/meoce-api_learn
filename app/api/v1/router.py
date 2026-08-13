""" V1 aggregator - mounted under /api/v1. """

from fastapi import APIRouter

from app.api.v1 import health, instruments

router =  APIRouter(prefix="/api/v1")


router.include_router(instruments.router)
router.include_router(health.router)

