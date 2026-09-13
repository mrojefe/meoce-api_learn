"""Billing -- checkout, webhook, and reconciliation orchestration around
GeniusPay. Only the code that moves money lives here -- catalog reads
(list_plans/list_features) live in app/services/plans.py, per JF: "billing
part must be the stuff who take the money."

This layer is deliberately NOT a port of the old frontend's Next.js payment
routes. The GeniusPay wire contract (app/services/payment_provider.py) is
followed as-is -- it is proven in production. How checkout is requested, how
a payment gets applied, and what this API exposes for it is designed fresh
for this codebase's conventions (named sql/params, transaction() for atomic
writes, the ApiError/ErrorCode contract).

The atomicity/idempotency shape below -- write the payment intent before
calling the provider, dedupe on a client-supplied idempotency_key, never trust
a webhook body alone in production -- mirrors the pattern proven in
_real_eg/meoce-frontend's payment routes, adapted to account_id and to this
service's own error contract.

Three purchase paths, per the design (Miro: "Every path a subscription can
take"): a fixed plan, a user-built custom plan (create_custom_plan() first,
then checkout_plan() like any other plan code), or a standalone addon
(checkout_addon(), independent of plan state, extends a user_features row
instead of a subscription).
"""

import secrets
from enum import StrEnum, unique

from psycopg.types.json import Jsonb

from app.core.db.database import query, transaction
from app.core.errors import ApiError, ConflictError, ErrorCode, ErrorStatus
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
    BLOCKED = "blocked"
    # BLOCKED: the anti-downgrade check refused to credit this payment.
    # Distinct from FAILED (the provider never completed it) and EXPIRED (we
    # gave up waiting) -- this one completed at GeniusPay, we chose not to
    # apply it. Counts as applied=true so reconcile_stuck_payments() leaves
    # it alone -- it is resolved, just not credited.


PAYMENT_PROVIDER_NAME = "geniuspay"
# NOTE: the literal provider name written into payments.provider /
# subscriptions.payment_provider. A constant, not a repeated string, so the
# day a second provider exists this is the one place to touch.

MIN_PERIODS_PURCHASED = 1
MAX_PERIODS_PURCHASED = 52
# NOTE: a sanity bound on user-chosen duration, not a business rule -- stops
# a typo'd or malicious "9999999 weeks" from producing an absurd amount_xof.


def _validate_periods_purchased(periods_purchased: int) -> None:
    """Raises if periods_purchased is outside the sane range. Shared by
    checkout_plan() and checkout_addon() -- same rule, same message, one
    place to change the bound.
    """
    if not (MIN_PERIODS_PURCHASED <= periods_purchased <= MAX_PERIODS_PURCHASED):
        raise ApiError(
            ErrorCode.VALIDATION,
            f"periods_purchased must be between {MIN_PERIODS_PURCHASED} and "
            f"{MAX_PERIODS_PURCHASED}, got {periods_purchased!r}",
            ErrorStatus.UNPROCESSABLE_ENTITY,
        )


def _weekly_rate(price_xof, interval: str, interval_count: int):
    """Normalises any plan/feature's price to a per-week rate, for the
    anti-downgrade comparison. Fixed convention (per the design): 1 month =
    4 weeks -- not a calendar month, a flat multiplier, so the comparison is
    stable regardless of which actual month it is.

    Args:
        price_xof: The plan or feature's own price_xof (Decimal from the DB).
        interval (str): "week" or "month".
        interval_count (int): How many of that interval one price_xof buys.

    Returns:
        Decimal: price_xof normalised to a single week.
    """
    weeks_covered = interval_count if interval == "week" else interval_count * 4
    return price_xof / weeks_covered * 4


def checkout_plan(user_id: str, plan_code: str, periods_purchased: int,
                   idempotency_key: str, success_url: str, error_url: str) -> dict:
    """Starts a checkout for a plan -- fixed, or a user's own custom plan
    (see create_custom_plan()). Writes the payment intent first, then calls
    GeniusPay for a hosted checkout URL.

    Writing the `payments` row *before* calling the provider means a crash or
    timeout mid-call leaves an auditable, pending row -- not a phantom charge
    with no record on our side.

    Idempotency: a second call with the same `idempotency_key` replays the
    existing `checkout_url` if the plan AND duration are unchanged, or raises
    if either differs -- a stale/reused client-generated key should never
    silently switch what gets paid for.

    Args:
        user_id (str): The authenticated caller.
        plan_code (str): Must be an active, priced plan. If it is a custom
            plan (kind='custom'), the caller must own it -- checked against
            the DB, not just PlanCode, since custom codes are never in that
            enum by design.
        periods_purchased (int): How many of the plan's own interval to buy,
            e.g. 5 (weeks), chosen by the user.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ApiError: PLAN_NOT_FOUND if plan_code is not an active, priced plan,
            or belongs to a different account. VALIDATION if
            periods_purchased is out of range.
        ConflictError: IDEMPOTENCY_KEY_REUSED if this key was already used
            for a different plan or duration.
    """
    _validate_periods_purchased(periods_purchased)

    sql_existing = """
        SELECT id, plan_code, periods_purchased, checkout_url, status
        FROM payments WHERE idempotency_key = %s
        """
    params_existing = (idempotency_key,)
    existing_rows = query(sql_existing, params_existing)

    # REVIEW: idempotency dedupe. Same key + same plan + same duration ->
    # replay the existing checkout_url (a retried request must not create a
    # second payment row). Anything else about the request differing -> reject
    # instead of silently switching what the caller ends up paying for. This
    # is the only thing standing between a client retry and a double charge.
    if existing_rows:
        existing = existing_rows[0]
        same_request = (existing["plan_code"] == plan_code
                         and existing["periods_purchased"] == periods_purchased)
        if not same_request:
            raise ConflictError(
                "this idempotency_key was already used for a different plan/duration",
                ErrorCode.IDEMPOTENCY_KEY_REUSED,
            )
        result = {
            "checkout_url": existing["checkout_url"],
            "reference": None,
            "status": existing["status"],
        }
        return result

    sql_plan = """
        SELECT price_xof, name, interval, interval_count, kind, owner_account_id
        FROM plans WHERE code = %s AND is_active = true AND price_xof > 0
        """
    params_plan = (plan_code,)
    plan_rows = query(sql_plan, params_plan)
    if not plan_rows:
        raise ApiError(ErrorCode.PLAN_NOT_FOUND,
                        f"{plan_code!r} is not a purchasable plan", ErrorStatus.NOT_FOUND)
    plan = plan_rows[0]

    if plan["kind"] == "custom" and plan["owner_account_id"] != user_id:
        # Deliberately the same error as "doesn't exist" -- a caller probing
        # someone else's custom plan code learns nothing from the response.
        raise ApiError(ErrorCode.PLAN_NOT_FOUND,
                        f"{plan_code!r} is not a purchasable plan", ErrorStatus.NOT_FOUND)

    amount_xof = plan["price_xof"] * plan["interval_count"] * periods_purchased

    sql_insert_pending = """
        INSERT INTO payments (account_id, idempotency_key, provider, environment,
                               plan_code, periods_purchased, amount_xof, currency_code, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'XOF', %s)
        RETURNING id
        """
    params_insert_pending = (user_id, idempotency_key, PAYMENT_PROVIDER_NAME,
                              "sandbox" if payment_provider.is_sandbox() else "live",
                              plan_code, periods_purchased, amount_xof, PaymentStatus.PENDING)
    payment_rows = query(sql_insert_pending, params_insert_pending)
    payment_id = payment_rows[0]["id"]

    metadata = {"payment_id": str(payment_id), "account_id": user_id, "plan_code": plan_code}
    provider_result = payment_provider.create_payment(
        amount_xof=amount_xof,
        description=f"MEOCE -- {plan['name']} x{periods_purchased}",
        success_url=success_url,
        error_url=error_url,
        metadata=metadata,
    )

    _write_checkout_result(payment_id, provider_result)

    result = {
        "checkout_url": provider_result["checkout_url"],
        "reference": provider_result["reference"],
        "status": provider_result["status"],
    }
    return result


def checkout_addon(user_id: str, feature_key: str, periods_purchased: int,
                    idempotency_key: str, success_url: str, error_url: str) -> dict:
    """Starts a checkout for a standalone addon feature -- independent of
    plan state, any time. Extends a user_features row rather than a
    subscription (see apply_payment_to_addon()). Same shape as
    checkout_plan(), addon_code instead of plan_code.

    Args:
        user_id (str): The authenticated caller.
        feature_key (str): Must be an active, priced, boolean-kind feature --
            a limit-kind feature has no unambiguous purchased value (what
            number would it grant?), so it is not purchasable here.
        periods_purchased (int): How many of the feature's own interval to
            buy.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ApiError: PLAN_NOT_FOUND if feature_key is not a purchasable addon
            (reused code -- "the thing you asked to buy doesn't exist" reads
            the same whether it's a plan or a feature). VALIDATION if
            periods_purchased is out of range.
        ConflictError: IDEMPOTENCY_KEY_REUSED if this key was already used
            for a different feature or duration.
    """
    _validate_periods_purchased(periods_purchased)

    sql_existing = """
        SELECT id, addon_code, periods_purchased, checkout_url, status
        FROM payments WHERE idempotency_key = %s
        """
    params_existing = (idempotency_key,)
    existing_rows = query(sql_existing, params_existing)

    if existing_rows:
        existing = existing_rows[0]
        same_request = (existing["addon_code"] == feature_key
                         and existing["periods_purchased"] == periods_purchased)
        if not same_request:
            raise ConflictError(
                "this idempotency_key was already used for a different addon/duration",
                ErrorCode.IDEMPOTENCY_KEY_REUSED,
            )
        result = {
            "checkout_url": existing["checkout_url"],
            "reference": None,
            "status": existing["status"],
        }
        return result

    sql_feature = """
        SELECT price_xof, label, interval, interval_count
        FROM features WHERE key = %s AND is_active = true AND kind = 'boolean' AND price_xof > 0
        """
    params_feature = (feature_key,)
    feature_rows = query(sql_feature, params_feature)
    if not feature_rows:
        raise ApiError(ErrorCode.PLAN_NOT_FOUND,
                        f"{feature_key!r} is not a purchasable addon", ErrorStatus.NOT_FOUND)
    feature = feature_rows[0]

    amount_xof = feature["price_xof"] * feature["interval_count"] * periods_purchased

    sql_insert_pending = """
        INSERT INTO payments (account_id, idempotency_key, provider, environment,
                               addon_code, periods_purchased, amount_xof, currency_code, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'XOF', %s)
        RETURNING id
        """
    params_insert_pending = (user_id, idempotency_key, PAYMENT_PROVIDER_NAME,
                              "sandbox" if payment_provider.is_sandbox() else "live",
                              feature_key, periods_purchased, amount_xof, PaymentStatus.PENDING)
    payment_rows = query(sql_insert_pending, params_insert_pending)
    payment_id = payment_rows[0]["id"]

    metadata = {"payment_id": str(payment_id), "account_id": user_id, "addon_code": feature_key}
    provider_result = payment_provider.create_payment(
        amount_xof=amount_xof,
        description=f"MEOCE -- {feature['label']} x{periods_purchased}",
        success_url=success_url,
        error_url=error_url,
        metadata=metadata,
    )

    _write_checkout_result(payment_id, provider_result)

    result = {
        "checkout_url": provider_result["checkout_url"],
        "reference": provider_result["reference"],
        "status": provider_result["status"],
    }
    return result


def _write_checkout_result(payment_id: str, provider_result: dict) -> None:
    """Shared by checkout_plan()/checkout_addon(): writes the provider's
    reference/checkout_url/status/raw-response back onto the pending
    payments row. Pulled out once both checkout paths needed the identical
    UPDATE.
    """
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


def create_custom_plan(user_id: str, feature_keys: list[str]) -> str:
    """Builds a user's own custom plan: a new `plans` row (kind='custom',
    owner_account_id=user_id) priced as the sum of the chosen features'
    price_xof, computed once and stored -- never recomputed live. The
    returned plan_code is then bought like any other plan, via
    checkout_plan().

    Scoped to boolean-kind features only -- same reasoning as
    checkout_addon(): a limit-kind feature has no single purchased value to
    grant.

    Args:
        user_id (str): The authenticated caller -- becomes owner_account_id.
        feature_keys (list[str]): Must be non-empty, every key must exist,
            be active, boolean-kind, and priced.

    Returns:
        str: The new plan's code (e.g. "custom_a1b2c3d4e5f6").

    Raises:
        ApiError: VALIDATION if feature_keys is empty, contains an unknown/
            inactive/non-boolean/unpriced key, or the chosen features don't
            share one interval/interval_count -- summing across different
            intervals would silently produce a wrong total, so this refuses
            instead of guessing.
    """
    unique_keys = list(dict.fromkeys(feature_keys))
    if not unique_keys:
        raise ApiError(ErrorCode.VALIDATION, "feature_keys must not be empty",
                        ErrorStatus.UNPROCESSABLE_ENTITY)

    sql_features = """
        SELECT key, price_xof, interval, interval_count
        FROM features
        WHERE key = ANY(%s) AND is_active = true AND kind = 'boolean' AND price_xof > 0
        """
    params_features = (unique_keys,)
    feature_rows = query(sql_features, params_features)

    found_keys = {row["key"] for row in feature_rows}
    missing_keys = set(unique_keys) - found_keys
    if missing_keys:
        raise ApiError(
            ErrorCode.VALIDATION,
            f"not purchasable, unknown, or not boolean-kind: {sorted(missing_keys)}",
            ErrorStatus.UNPROCESSABLE_ENTITY,
        )

    intervals = {(row["interval"], row["interval_count"]) for row in feature_rows}
    if len(intervals) > 1:
        raise ApiError(
            ErrorCode.VALIDATION,
            "the chosen features do not share one interval/interval_count -- "
            "cannot sum their prices into a single plan price",
            ErrorStatus.UNPROCESSABLE_ENTITY,
        )
    interval, interval_count = intervals.pop()

    total_price_xof = sum(row["price_xof"] for row in feature_rows)
    plan_code = f"custom_{secrets.token_hex(6)}"

    with transaction() as conn:
        sql_insert_plan = """
            INSERT INTO plans (code, name, kind, owner_account_id, price_xof,
                                interval, interval_count, is_active, display_order)
            VALUES (%s, %s, 'custom', %s, %s, %s, %s, true, 0)
            """
        params_insert_plan = (plan_code, f"Custom plan ({len(unique_keys)} features)",
                               user_id, total_price_xof, interval, interval_count)
        conn.execute(sql_insert_plan, params_insert_plan)

        sql_insert_features = """
            INSERT INTO plan_features (plan_code, feature_key, value)
            VALUES (%s, %s, %s)
            """
        for feature_key in found_keys:
            params_insert_features = (plan_code, feature_key, Jsonb(True))
            conn.execute(sql_insert_features, params_insert_features)

    return plan_code


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
    the webhook body) and credits it -- to a subscription or to a
    user_features addon grant, whichever this payment is for -- all inside
    one transaction, so a payment is never marked completed without also
    being credited, or vice versa.

    Args:
        reference (str): GeniusPay's reference for this payment.
        provider_status (dict): Whatever get_payment_status() returned (or,
            sandbox-only, the trusted webhook payload).
    """
    if provider_status.get("status") != PaymentStatus.COMPLETED:
        return

    # REVIEW: this is the actual money-crediting path. mark-completed +
    # the credit call + the audit event all run inside one transaction() --
    # a payment must never end up "completed" without also being credited,
    # or vice versa. `WHERE applied = false` in _find below is what makes
    # this safe to call twice for the same reference (webhook retry, then
    # reconcile catching the same payment): the second call finds no row and
    # returns without crediting again.
    with transaction() as conn:
        sql_find = """
            SELECT id, account_id, plan_code, addon_code
            FROM payments WHERE reference = %s AND applied = false
            """
        params_find = (reference,)
        row = conn.execute(sql_find, params_find).fetchone()
        if row is None:
            return
        payment_id = row["id"]

        if row["addon_code"] is not None:
            _credit_addon(conn, payment_id, reference)
        else:
            _credit_plan(conn, payment_id, reference, row["account_id"], row["plan_code"])


def _credit_plan(conn, payment_id: str, reference: str, account_id: str, plan_code: str) -> None:
    """The plan-purchase half of _apply_verified_status(): the anti-downgrade
    check, then either block or credit. Runs inside the caller's transaction.
    """
    sql_new_plan = "SELECT price_xof, interval, interval_count FROM plans WHERE code = %s"
    params_new_plan = (plan_code,)
    new_plan = conn.execute(sql_new_plan, params_new_plan).fetchone()
    new_rate = _weekly_rate(new_plan["price_xof"], new_plan["interval"], new_plan["interval_count"])

    # REVIEW: anti-downgrade. An account already on a paid, unexpired plan
    # must not have this payment silently swap it for a cheaper one -- e.g. a
    # stale checkout link for a plan since discontinued in favour of a
    # pricier one. Rates are normalised to a weekly figure (1 month = 4
    # weeks, fixed convention) so a week-priced and month-priced plan compare
    # like for like.
    sql_current = """
        SELECT p.price_xof, p.interval, p.interval_count
        FROM subscriptions AS s
        JOIN plans AS p ON p.code = s.plan_code
        WHERE s.account_id = %s AND s.status = 'active'
          AND s.current_period_end > now()
        ORDER BY s.created_at DESC LIMIT 1
        """
    params_current = (account_id,)
    current = conn.execute(sql_current, params_current).fetchone()

    if current is not None:
        current_rate = _weekly_rate(current["price_xof"], current["interval"], current["interval_count"])
        if new_rate < current_rate:
            sql_block = "UPDATE payments SET applied = true, status = %s WHERE id = %s"
            params_block = (PaymentStatus.BLOCKED, payment_id)
            conn.execute(sql_block, params_block)

            sql_event_blocked = """
                INSERT INTO payment_events (payment_id, reference, event_type, status, source)
                VALUES (%s, %s, 'downgrade_blocked', %s, 'reconcile_or_webhook')
                """
            params_event_blocked = (payment_id, reference, PaymentStatus.BLOCKED)
            conn.execute(sql_event_blocked, params_event_blocked)
            return

    sql_mark_completed = "UPDATE payments SET status = %s WHERE id = %s"
    params_mark_completed = (PaymentStatus.COMPLETED, payment_id)
    conn.execute(sql_mark_completed, params_mark_completed)

    sql_apply = "SELECT apply_payment_to_subscription(%s)"
    params_apply = (payment_id,)
    conn.execute(sql_apply, params_apply)

    sql_event = """
        INSERT INTO payment_events (payment_id, reference, event_type, status, source)
        VALUES (%s, %s, 'payment.completed', %s, 'reconcile_or_webhook')
        """
    params_event = (payment_id, reference, PaymentStatus.COMPLETED)
    conn.execute(sql_event, params_event)


def _credit_addon(conn, payment_id: str, reference: str) -> None:
    """The addon-purchase half of _apply_verified_status(): no
    anti-downgrade check (addons are independent of plan state, per the
    design), straight to crediting. Runs inside the caller's transaction.
    """
    sql_mark_completed = "UPDATE payments SET status = %s WHERE id = %s"
    params_mark_completed = (PaymentStatus.COMPLETED, payment_id)
    conn.execute(sql_mark_completed, params_mark_completed)

    sql_apply = "SELECT apply_payment_to_addon(%s)"
    params_apply = (payment_id,)
    conn.execute(sql_apply, params_apply)

    sql_event = """
        INSERT INTO payment_events (payment_id, reference, event_type, status, source)
        VALUES (%s, %s, 'payment.completed', %s, 'reconcile_or_webhook')
        """
    params_event = (payment_id, reference, PaymentStatus.COMPLETED)
    conn.execute(sql_event, params_event)
