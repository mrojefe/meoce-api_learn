"""Billing routes -- HTTP only. The work happens in the service."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.core.security.deps import get_current_user_id, require_api_key
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
from app.schemas.plans import Plan
from app.services import billing

router = APIRouter(tags=["billing"])


@router.get("/plans", response_model=Envelope[list[Plan]])
def list_plans():
    """Lists every active, purchasable plan -- public, no auth. What the
    frontend's plan-picker renders before anyone has picked anything.

    Returns:
        dict: {"data": [...]}.
    """
    return envelope_(data=billing.list_plans())


@router.post("/billing/checkout", response_model=Envelope[dict],
             responses={x: {"model": ErrorEnvelope} for x in [401, 404, 409]})
def start_checkout(payload: dict, user_id: Annotated[str, Depends(get_current_user_id)]):
    """Starts a checkout for a paid plan and returns GeniusPay's hosted
    checkout URL.

    Args:
        payload (dict): {"plan_code", "idempotency_key", "success_url",
            "error_url"}. A plain dict rather than a schema for now -- this
            is the first write-side billing endpoint; a dedicated
            CheckoutRequest schema is worth adding once the frontend's real
            shape is settled.
        user_id (str): The authenticated caller.

    Returns:
        dict: {"data": {"checkout_url": ..., "reference": ..., "status": ...}}.
    """
    result = billing.start_checkout(
        user_id=user_id,
        plan_code=payload["plan_code"],
        idempotency_key=payload["idempotency_key"],
        success_url=payload["success_url"],
        error_url=payload["error_url"],
    )
    return envelope_(data=result)


@router.post("/billing/webhook", status_code=204)
async def receive_webhook(request: Request):
    """GeniusPay's webhook delivery endpoint -- no auth (the provider calls
    this directly). Authenticity is established inside billing.handle_webhook
    via signature verification + a re-check against the provider's own
    status, never trusted from headers alone.

    Args:
        request (Request): Used directly (not a Pydantic body) because
            signature verification needs the exact raw bytes GeniusPay sent,
            before any JSON parsing.
    """
    raw_body = await request.body()
    headers = {k.lower(): v for k, v in request.headers.items()}
    billing.handle_webhook(raw_body, headers)


@router.post("/billing/reconcile", response_model=Envelope[dict],
             dependencies=[Depends(require_api_key)])
def reconcile():
    """Re-checks stuck payments against GeniusPay's real status. Internal
    only -- gated by X-API-KEY, meant to be called by a scheduled job
    (Airflow), not by a browser. Catches a webhook GeniusPay sent but this
    API never received or failed to process.

    Returns:
        dict: {"data": {"reconciled": N, "expired": N}}.
    """
    return envelope_(data=billing.reconcile_stuck_payments())
