"""Billing routes -- HTTP only. Checkout/custom-plan work happens in
purchasing.py (what a purchase means); webhook/reconcile work happens in
billing.py (the payment mechanic itself)."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.core.security.deps import get_current_user_id, require_api_key
from app.schemas.common import Envelope, ErrorEnvelope, envelope_
from app.services import billing, purchasing

router = APIRouter(prefix="/billing", tags=["billing"])


@router.post("/checkout", response_model=Envelope[dict],
             responses={x: {"model": ErrorEnvelope} for x in [401, 404, 409, 422]})
def checkout_plan(payload: dict, user_id: Annotated[str, Depends(get_current_user_id)]):
    """Starts a checkout for a plan (fixed, or the caller's own custom plan)
    and returns GeniusPay's hosted checkout URL.

    Args:
        payload (dict): {"plan_code", "periods_purchased", "idempotency_key",
            "success_url", "error_url"}. A plain dict rather than a schema for
            now -- this is an early write-side billing endpoint; a dedicated
            CheckoutRequest schema is worth adding once the frontend's real
            shape is settled.
        user_id (str): The authenticated caller.

    Returns:
        dict: {"data": {"checkout_url": ..., "reference": ..., "status": ...}}.
    """
    result = purchasing.checkout_plan(
        user_id=user_id,
        plan_code=payload["plan_code"],
        periods_purchased=payload["periods_purchased"],
        idempotency_key=payload["idempotency_key"],
        success_url=payload["success_url"],
        error_url=payload["error_url"],
    )
    return envelope_(data=result)


@router.post("/checkout/addon", response_model=Envelope[dict],
             responses={x: {"model": ErrorEnvelope} for x in [401, 404, 409, 422]})
def checkout_addon(payload: dict, user_id: Annotated[str, Depends(get_current_user_id)]):
    """Starts a checkout for a standalone addon feature -- independent of
    plan state, any time.

    Args:
        payload (dict): {"feature_key", "periods_purchased",
            "idempotency_key", "success_url", "error_url"}.
        user_id (str): The authenticated caller.

    Returns:
        dict: {"data": {"checkout_url": ..., "reference": ..., "status": ...}}.
    """
    result = purchasing.checkout_addon(
        user_id=user_id,
        feature_key=payload["feature_key"],
        periods_purchased=payload["periods_purchased"],
        idempotency_key=payload["idempotency_key"],
        success_url=payload["success_url"],
        error_url=payload["error_url"],
    )
    return envelope_(data=result)


@router.post("/custom-plan", response_model=Envelope[dict], status_code=201,
             responses={x: {"model": ErrorEnvelope} for x in [401, 422]})
def create_custom_plan(payload: dict, user_id: Annotated[str, Depends(get_current_user_id)]):
    """Builds the caller's own custom plan from picked features. Returns the
    new plan_code, which the frontend then passes to POST /billing/checkout
    like any other plan.

    Args:
        payload (dict): {"feature_keys": [...]}.
        user_id (str): The authenticated caller -- becomes the plan's owner.

    Returns:
        dict: {"data": {"plan_code": "custom_..."}}.
    """
    plan_code = purchasing.create_custom_plan(user_id=user_id, feature_keys=payload["feature_keys"])
    return envelope_(data={"plan_code": plan_code})


@router.post("/webhook", status_code=204)
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


@router.post("/reconcile", response_model=Envelope[dict],
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
