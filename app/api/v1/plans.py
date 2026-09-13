"""Plans and features routes -- HTTP only. Public catalog, no auth, no money.
The work happens in the service."""

from fastapi import APIRouter

from app.schemas.common import Envelope, envelope_
from app.schemas.plans import Plan
from app.services import plans as services

router = APIRouter(tags=["plans"])


@router.get("/plans", response_model=Envelope[list[Plan]])
def list_plans():
    """Lists every active, fixed, purchasable plan -- public, no auth. What
    the frontend's plan-picker renders before anyone has picked anything.

    Returns:
        dict: {"data": [...]}.
    """
    return envelope_(data=services.list_plans())


@router.get("/features", response_model=Envelope[list[dict]])
def list_features():
    """Lists every active, purchasable addon feature -- public, no auth.

    Returns:
        dict: {"data": [...]}.
    """
    return envelope_(data=services.list_features())
