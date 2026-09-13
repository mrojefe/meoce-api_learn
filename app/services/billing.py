"""Billing -- checkout, webhook, and reconciliation orchestration around
GeniusPay.

This layer is deliberately NOT a port of the old frontend's Next.js payment
routes. The GeniusPay wire contract (app/services/payment_provider.py) is followed
as-is -- it is proven in production. How checkout is requested, how a payment
gets applied, and what this API exposes for it is designed fresh for this
codebase's conventions (named sql/params, transaction() for atomic writes,
the ApiError/ErrorCode contract).

The atomicity/idempotency shape below -- write the payment intent before
calling the provider, dedupe on a client-supplied idempotency_key, never trust
a webhook body alone in production -- mirrors the pattern proven in
_real_eg/meoce-frontend's payment routes, adapted to account_id and to this
service's own error contract.
"""

from enum import StrEnum, unique

from psycopg.types.json import Jsonb

from app.core.db.database import query, transaction
from app.core.errors import ApiError, ConflictError, ErrorCode, ErrorStatus
from app.core.reference import PlanCode
from app.schemas.plans import Plan, PlanFeatures
from app.services import payment_provider


@unique
class PaymentStatus(StrEnum):
    """payments.status's real values. Not DB-enforced (no CHECK constraint --
    verified directly against meoce_prod, 2026-09-13), so nothing else stops
    a typo from writing a status this code, or anyone reading the table,
    would not recognise.
    """

    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"
    EXPIRED = "expired"


PAYMENT_PROVIDER_NAME = "geniuspay"
# NOTE: the literal provider name written into payments.provider /
# subscriptions.payment_provider. A constant, not a repeated string, so the
# day a second provider exists this is the one place to touch.


def list_plans() -> list[Plan]:
    """Every active plan, priced and with its features, for the frontend's
    plan-picker. No caller -- this is the same for everyone.

    Returns:
        list[Plan]: Ordered by `display_order`, the same order the plans
            table itself defines for presentation.
    """
    sql_plans = """
        SELECT code, name, price_xof, interval, interval_count
        FROM plans
        WHERE is_active = true
        ORDER BY display_order
        """
    plan_rows = query(sql_plans)

    sql_features = "SELECT feature_key, value FROM plan_features WHERE plan_code = %s"

    plans = []
    for plan_row in plan_rows:
        params_features = (plan_row["code"],)
        feature_rows = query(sql_features, params_features)
        features = {row["feature_key"]: row["value"] for row in feature_rows}
        plan = Plan(**plan_row, features=PlanFeatures(**features))
        plans.append(plan)

    return plans


def start_checkout(user_id: str, plan_code: str, idempotency_key: str,
                    success_url: str, error_url: str) -> dict:
    """Starts a checkout for a paid plan: writes the payment intent first,
    then calls GeniusPay for a hosted checkout URL.

    Writing the `payments` row *before* calling the provider means a crash or
    timeout mid-call leaves an auditable, pending row -- not a phantom charge
    with no record on our side.

    Idempotency: a second call with the same `idempotency_key` replays the
    existing `checkout_url` if the plan is unchanged, or raises if the caller
    is trying to check out a different plan under a key already used for
    another one -- a stale/reused client-generated key should never silently
    switch what gets paid for.

    Args:
        user_id (str): The authenticated caller.
        plan_code (str): Must be an active, paid plan -- validated against
            PlanCode and the plans table, not trusted from the client alone.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ApiError: PLAN_NOT_FOUND if plan_code is not an active plan.
        ConflictError: IDEMPOTENCY_KEY_REUSED if this key was already used for
            a different plan.
    """
    if plan_code not in {PlanCode.PLUS, PlanCode.PRO}:
        raise ApiError(ErrorCode.PLAN_NOT_FOUND,
                        f"{plan_code!r} is not a purchasable plan", ErrorStatus.NOT_FOUND)

    sql_existing = "SELECT id, plan_code, checkout_url, status FROM payments WHERE idempotency_key = %s"
    params_existing = (idempotency_key,)
    existing_rows = query(sql_existing, params_existing)

    # REVIEW: idempotency dedupe. Same key + same plan -> replay the existing
    # checkout_url (a retried request must not create a second payment row).
    # Same key + a DIFFERENT plan -> reject instead of silently switching what
    # the caller ends up paying for. This is the only thing standing between
    # a client retry and a double charge -- please look at this branch.
    if existing_rows:
        existing = existing_rows[0]
        if existing["plan_code"] != plan_code:
            raise ConflictError(
                "this idempotency_key was already used for a different plan",
                ErrorCode.IDEMPOTENCY_KEY_REUSED,
            )
        result = {
            "checkout_url": existing["checkout_url"],
            "reference": None,
            "status": existing["status"],
        }
        return result

    sql_plan = "SELECT price_xof, name FROM plans WHERE code = %s AND is_active = true"
    params_plan = (plan_code,)
    plan_rows = query(sql_plan, params_plan)
    if not plan_rows:
        raise ApiError(ErrorCode.PLAN_NOT_FOUND,
                        f"{plan_code!r} is not a purchasable plan", ErrorStatus.NOT_FOUND)
    plan = plan_rows[0]

    sql_insert_pending = """
        INSERT INTO payments (account_id, idempotency_key, provider, environment,
                               plan_code, periods_purchased, amount_xof, currency_code, status)
        VALUES (%s, %s, %s, %s, %s, 1, %s, 'XOF', %s)
        RETURNING id
        """
    params_insert_pending = (user_id, idempotency_key, PAYMENT_PROVIDER_NAME,
                              "sandbox" if payment_provider.is_sandbox() else "live",
                              plan_code, plan["price_xof"], PaymentStatus.PENDING)
    payment_rows = query(sql_insert_pending, params_insert_pending)
    payment_id = payment_rows[0]["id"]

    metadata = {"payment_id": str(payment_id), "account_id": user_id, "plan_code": plan_code}
    provider_result = payment_provider.create_payment(
        amount_xof=plan["price_xof"],
        description=f"MEOCE -- {plan['name']}",
        success_url=success_url,
        error_url=error_url,
        metadata=metadata,
    )

    # NOTE: provider_result["status"] is GeniusPay's own string (e.g. it may
    # return null->normalised-to-"pending" on creation), not PaymentStatus --
    # written through as-is rather than mapped, since sandbox has already been
    # observed to return values not in PaymentStatus (see payment_provider.py).
    sql_update_reference = """
        UPDATE payments
        SET reference = %s, checkout_url = %s, status = %s, create_response = %s
        WHERE id = %s
        """
    params_update_reference = (provider_result["reference"], provider_result["checkout_url"],
                                provider_result["status"], Jsonb(provider_result["raw"]), payment_id)
    query(sql_update_reference, params_update_reference, nothing_return=True)

    result = {
        "checkout_url": provider_result["checkout_url"],
        "reference": provider_result["reference"],
        "status": provider_result["status"],
    }
    return result


def handle_webhook(raw_body: bytes, headers: dict) -> None:
    """Handles one GeniusPay webhook delivery.

    Never applies a credit from the webhook body alone in production. The
    signature is checked first; regardless of that result, the payment's real
    status is re-confirmed with GeniusPay itself via get_payment_status()
    before anything is applied -- the webhook is a nudge to look, not proof.
    The one exception: sandbox, with no other proof available, may trust the
    payload -- gated by payment_provider.is_sandbox(), which requires both a
    non-production runtime AND a sandbox key.

    Args:
        raw_body (bytes): The exact request body GeniusPay sent.
        headers (dict): Request headers, lower-cased keys.

    Raises:
        ApiError: UNAUTHORIZED if the signature is present and invalid or
            expired. An absent/unverifiable signature is NOT rejected here --
            it falls through to the provider status re-check, same as the
            proven real-prod pattern.
    """
    import json

    from app.core.errors import UnauthorizedError

    signature_result = payment_provider.verify_webhook_signature(raw_body, headers)
    if signature_result in ("invalid", "expired"):
        raise UnauthorizedError(f"webhook signature {signature_result}")

    # REVIEW: an "unverified" signature (no secret configured, or the
    # signature/timestamp headers were absent) is deliberately NOT rejected
    # here -- it falls through to re-checking GeniusPay's real status below,
    # same as the proven real-prod pattern. Only "invalid"/"expired" (a
    # signature that was PRESENT and wrong) raises above. Please confirm this
    # reads right to you -- this is the one branch between a spoofed request
    # and a credited payment if get_payment_status() below were ever bypassed.
    payload = json.loads(raw_body)
    reference = (payload.get("data") or {}).get("reference") or payload.get("reference")
    if not reference:
        return

    try:
        provider_status = payment_provider.get_payment_status(reference)
    except RuntimeError:
        # REVIEW: only reachable if the provider call itself fails (network,
        # 4xx/5xx) AND the signature was valid AND this is sandbox. Never in
        # production -- is_sandbox() requires a non-prod runtime AND a
        # sandbox key, both, so a mis-set env var alone cannot open this path.
        if signature_result == "valid" and payment_provider.is_sandbox():
            provider_status = (payload.get("data") or payload)
        else:
            raise

    _apply_verified_status(reference, provider_status)


def reconcile_stuck_payments() -> dict:
    """Re-checks every un-applied, non-expired payment with a reference
    against GeniusPay's real status -- catches a webhook GeniusPay sent but
    this API never received or failed to process.

    Also expires referenceless payments (the provider call itself failed,
    before a reference ever came back) after 30 minutes -- they cannot be
    reconciled, since there is nothing to look up.

    Meant to be called periodically (Airflow, matching real prod's
    dag_payments_reconcile.py), not by a browser -- see the internal-only
    route in app/api/v1/billing.py.

    Returns:
        dict: reconciled (count applied), expired (count marked expired).
    """
    sql_stuck = """
        SELECT id, reference FROM payments
        WHERE applied = false AND reference IS NOT NULL AND status != %s
        """
    params_stuck = (PaymentStatus.EXPIRED,)
    stuck_rows = query(sql_stuck, params_stuck)

    reconciled = 0
    for row in stuck_rows:
        try:
            provider_status = payment_provider.get_payment_status(row["reference"])
        except RuntimeError as error:
            if getattr(error, "not_found", False):
                continue
            raise
        if provider_status["status"] == PaymentStatus.COMPLETED:
            _apply_verified_status(row["reference"], provider_status)
            reconciled += 1

    sql_expire = """
        UPDATE payments
        SET status = %s
        WHERE applied = false AND reference IS NULL
          AND status = %s AND created_at < now() - interval '30 minutes'
        RETURNING id
        """
    params_expire = (PaymentStatus.EXPIRED, PaymentStatus.PENDING)
    expired_rows = query(sql_expire, params_expire)

    result = {"reconciled": reconciled, "expired": len(expired_rows)}
    return result


def _apply_verified_status(reference: str, provider_status: dict) -> None:
    """Marks the payment `completed` (from the provider's own status, never
    the webhook body) and credits it via apply_payment_to_subscription() --
    all inside one transaction, so a payment is never marked completed
    without also being credited, or vice versa.

    Args:
        reference (str): GeniusPay's reference for this payment.
        provider_status (dict): Whatever get_payment_status() returned (or,
            sandbox-only, the trusted webhook payload).
    """
    if provider_status.get("status") != PaymentStatus.COMPLETED:
        return

    # REVIEW: this is the actual money-crediting path. mark-completed +
    # apply_payment_to_subscription() + the audit event all run inside one
    # transaction() -- a payment must never end up "completed" without also
    # being credited, or vice versa. `WHERE applied = false` in _find below is
    # what makes this safe to call twice for the same reference (webhook
    # retry, then reconcile catching the same payment): the second call finds
    # no row and returns without crediting again.
    with transaction() as conn:
        sql_find = "SELECT id FROM payments WHERE reference = %s AND applied = false"
        params_find = (reference,)
        row = conn.execute(sql_find, params_find).fetchone()
        if row is None:
            return
        payment_id = row["id"]

        sql_mark_completed = "UPDATE payments SET status = %s WHERE id = %s"
        params_mark_completed = (PaymentStatus.COMPLETED, payment_id)
        conn.execute(sql_mark_completed, params_mark_completed)

        sql_apply = "SELECT apply_payment_to_subscription(%s)"
        params_apply = (payment_id,)
        conn.execute(sql_apply, params_apply)

        sql_event = """
            INSERT INTO payment_events (payment_id, reference, event_type, status, source)
            VALUES (%s, %s, %s, %s, %s)
            """
        params_event = (payment_id, reference, "payment.completed",
                         PaymentStatus.COMPLETED, "reconcile_or_webhook")
        conn.execute(sql_event, params_event)
