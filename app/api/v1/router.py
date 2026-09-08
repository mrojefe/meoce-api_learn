""" V1 aggregator - mounted under /api/v1. """

from fastapi import APIRouter

from app.api.v1 import (
    auth,
    drawings,
    entitlements,
    flags,
    health,
    instruments,
    notification_settings,
    reference,
    subscription,
    user_preferences,
    user_profile,
    watchlists,
    whatsapp_auth,
)

router =  APIRouter(prefix="/api/v1")


router.include_router(instruments.router)
router.include_router(health.router)
router.include_router(watchlists.router)
router.include_router(flags.router)
router.include_router(user_preferences.router)
router.include_router(reference.router)
router.include_router(user_profile.router)
router.include_router(entitlements.router)
router.include_router(subscription.router)
router.include_router(drawings.router)
router.include_router(notification_settings.router)
router.include_router(auth.router)
router.include_router(whatsapp_auth.router)
