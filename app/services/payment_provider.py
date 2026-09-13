"""Payment provider client -- SERVER-ONLY. Currently GeniusPay.

Named payment_provider, not geniuspay: billing.py and every route depend on
this module's function names (create_payment, get_payment_status,
verify_webhook_signature, is_sandbox), never on the provider's own name --
swapping providers later means rewriting this one file, not every caller.

The wire contract implemented here (auth headers, request/response shape,
webhook signature scheme) is ported from the real, production-proven client
at `_real_eg/meoce-frontend/src/lib/payments/geniuspay.ts` -- that part is
fine to follow as-is, per JF. What is NOT ported from there is how checkout/
webhook/reconciliation are orchestrated around this client -- that is
app/services/billing.py, written fresh for this codebase.

Never import this module from anything reachable by a browser bundle -- it
reads GENIUSPAY_API_SECRET.
"""

import hashlib
import hmac
import time

import httpx

from app.core.config import get_settings


def _auth_headers() -> dict:
    """Headers GeniusPay accepts. Bearer always; X-API-Key/-Secret too if a
    public key is configured -- verified against their sandbox to accept
    either scheme.
    """
    settings = get_settings()
    secret = settings.geniuspay_api_secret.get_secret_value()

    headers = {
        "Authorization": f"Bearer {secret}",
        "Content-Type": "application/json",
    }
    if settings.geniuspay_api_key:
        headers["X-API-Key"] = settings.geniuspay_api_key
        headers["X-API-Secret"] = secret

    return headers


def is_sandbox() -> bool:
    """True only when BOTH this process is not production AND the configured
    secret is itself a sandbox key.

    Two independent conditions, not one: trusting the key's name alone would
    let a mis-named production key silently behave like sandbox (accepting an
    unverified webhook payload as proof of payment). This mirrors the real
    client's hardened isSandbox(), applied after a security review there.

    Returns:
        bool: Whether webhook handling may fall back to trusting the raw
            payload when no other proof is available.
    """
    settings = get_settings()

    if settings.env == "prod":
        return False

    secret = settings.geniuspay_api_secret.get_secret_value()
    return "sandbox" in secret


def verify_webhook_signature(raw_body: bytes, headers: dict) -> str:
    """Verifies a GeniusPay webhook per their documented scheme.

    signature = HMAC-SHA256(timestamp + "." + raw_body, webhook_secret)
    Header names arrive lower-cased by FastAPI's Headers object.

    Args:
        raw_body (bytes): The exact bytes GeniusPay sent, unparsed.
        headers (dict): Request headers, lower-cased keys.

    Returns:
        str: "valid", "invalid", "expired" (outside the 5-minute anti-replay
            window), or "unverified" (no secret configured, or the signature/
            timestamp headers are absent -- caller must fall back to
            get_payment_status(), never to trusting the payload).
    """
    settings = get_settings()
    secret = settings.geniuspay_webhook_secret.get_secret_value()
    if not secret:
        return "unverified"

    provided = headers.get("x-webhook-signature")
    timestamp = headers.get("x-webhook-timestamp")
    if not provided or not timestamp:
        return "unverified"

    try:
        ts = float(timestamp)
    except ValueError:
        return "unverified"

    if abs(time.time() - ts) > 300:
        return "expired"

    provided_hex = provided.removeprefix("sha256=").strip()
    signed_payload = f"{timestamp}.".encode() + raw_body
    expected = hmac.new(secret.encode(), signed_payload, hashlib.sha256).hexdigest()

    if hmac.compare_digest(expected, provided_hex):
        return "valid"

    return "invalid"


def create_payment(amount_xof: int, description: str, success_url: str,
                    error_url: str, metadata: dict) -> dict:
    """Creates a payment and returns the hosted checkout page's URL.

    `payment_method` is deliberately omitted from the request body: GeniusPay
    then returns a `checkout_url` where the customer picks Wave/Orange/MTN/
    Moov/card themselves, rather than this API committing to one operator.

    Args:
        amount_xof (int): Amount in XOF (GeniusPay's only supported currency
            here).
        description (str): Shown to the customer on the checkout page.
        success_url (str): Where the browser returns to after a successful
            payment.
        error_url (str): Where the browser returns to after a failed payment.
        metadata (dict): Round-tripped verbatim in the webhook and in
            get_payment_status() -- this is how billing.py recognises which
            payment a webhook is about.

    Returns:
        dict: reference, checkout_url, status, amount, raw (the full,
            untouched provider response -- kept for audit, nothing thrown
            away).

    Raises:
        RuntimeError: The provider returned an error, or a success response
            missing reference/checkout_url.
    """
    settings = get_settings()
    body = {
        "amount": amount_xof,
        "currency": "XOF",
        "description": description,
        "success_url": success_url,
        "error_url": error_url,
        "metadata": metadata,
    }

    response = httpx.post(f"{settings.geniuspay_base_url}/payments",
                           json=body, headers=_auth_headers(), timeout=15.0)
    payload = response.json()

    if not response.is_success or not payload.get("success"):
        message = (payload.get("error") or {}).get("message") or payload.get("message")             or f"HTTP {response.status_code}"
        raise RuntimeError(f"GeniusPay create_payment: {message}")

    data = payload.get("data") or {}
    checkout_url = data.get("checkout_url") or data.get("payment_url")
    if not data.get("reference") or not checkout_url:
        raise RuntimeError("GeniusPay create_payment: response missing reference/checkout_url")

    result = {
        "reference": data["reference"],
        "checkout_url": checkout_url,
        # Sandbox returns status=null on creation -- normalised to 'pending'
        # to match the payments table's CHECK constraint.
        "status": data.get("status") or "pending",
        "amount": data.get("amount", amount_xof),
        "raw": payload,
    }
    return result


def get_payment_status(reference: str) -> dict:
    """Reads a payment's REAL status from GeniusPay -- the source of truth
    for both webhook verification and reconciliation.

    Args:
        reference (str): The GeniusPay reference returned by create_payment().

    Returns:
        dict: reference, status, amount, payment_method, metadata,
            completed_at.

    Raises:
        RuntimeError: The provider returned an error. Carries `.not_found =
            True` when the provider returned 404 -- billing.py's
            reconciliation job treats that as "not a real payment on this
            environment" rather than an outage worth retrying forever.
    """
    settings = get_settings()
    response = httpx.get(f"{settings.geniuspay_base_url}/payments/{reference}",
                          headers=_auth_headers(), timeout=15.0)
    payload = response.json()

    if not response.is_success or not payload.get("success"):
        message = (payload.get("error") or {}).get("message") or payload.get("message")             or f"HTTP {response.status_code}"
        error = RuntimeError(f"GeniusPay get_payment_status: {message}")
        error.not_found = response.status_code == 404
        raise error

    data = payload.get("data") or {}
    result = {
        "reference": data.get("reference"),
        "status": data.get("status"),
        "amount": data.get("amount", 0),
        "payment_method": data.get("payment_method"),
        "metadata": data.get("metadata") or {},
        "completed_at": data.get("completed_at"),
    }
    return result
