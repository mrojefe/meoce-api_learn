""" V1 aggregator - mounted under /api/v1. """

from fastapi import APIRouter

from app.api.v1 import flags, health, instruments, preferences, reference, watchlists

router =  APIRouter(prefix="/api/v1")


router.include_router(instruments.router)
router.include_router(health.router)
router.include_router(watchlists.router)
router.include_router(flags.router)
router.include_router(preferences.router)
router.include_router(reference.router)

