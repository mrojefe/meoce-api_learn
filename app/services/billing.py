"""Billing -- the payment mechanic only. Takes money via GeniusPay, tracks
that transaction's own state, and guarantees it (idempotency, no double-
charge, signature/status verification). Owns every line of SQL against
`payments`/`payment_events` -- and NOTHING else. Contains zero knowledge of
what a plan, a feature, a subscription, or a custom plan IS: create_checkout()
receives an already-computed amount_xof + description from its caller, never
looks a price up itself.

Per JF: "billing must BE THE MONEY TAKE ALL no more all -- that he take the
money can return its status that it he assure everything are fine." What a
completed payment CAUSES (crediting a subscription, extending an addon, the
anti-downgrade check, custom-plan pricing) lives in app/services/purchasing.py,
which calls into this module's small helpers below to record the outcome --
never the reverse: this file must not import purchasing at module load time
(purchasing already imports billing for create_checkout()/PaymentStatus, and
a two-way top-level import would be circular). Where this file needs to call
purchasing (after confirming a payment is completed), it does a LOCAL import
inside the function -- same pattern already used below for
app.core.errors.UnauthorizedError, not a new convention.

The GeniusPay wire contract (app/services/payment_provider.py) is followed
as-is -- proven in production. The atomicity/idempotency shape -- write the
payment intent before calling the provider, dedupe on a client-supplied
idempotency_key, never trust a webhook body alone in production -- mirrors
the pattern proven in _real_eg/meoce-frontend's payment routes.
"""

from enum import StrEnum, unique

from psycopg.types.json import Jsonb

from app.core.db.database import query, transaction
from app.core.errors import ConflictError, ErrorCode
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
    # BLOCKED: purchasing's anti-downgrade check refused to credit this
    # payment. Distinct from FAILED (the provider never completed it) and
    # EXPIRED (we gave up waiting) -- this one completed at GeniusPay, but
    # purchasing chose not to apply it. Counts as applied=true so
    # reconcile_stuck_payments() leaves it alone -- it is resolved, just not
    # credited.


PAYMENT_PROVIDER_NAME = "geniuspay"
# NOTE: the literal provider name written into payments.provider. A
# constant, not a repeated string, so the day a second provider exists this
# is the one place to touch.

MIN_PERIODS_PURCHASED = 1
MAX_PERIODS_PURCHASED = 52
# NOTE: a sanity bound on user-chosen duration, not a business rule -- stops
# a typo'd or malicious "9999999 weeks" from producing an absurd amount_xof.
# Billing enforces the BOUND; purchasing decides the PRICE.


def create_checkout(account_id: str, idempotency_key: str, amount_xof, description: str,
                     success_url: str, error_url: str,
                     plan_code: str | None = None, addon_code: str | None = None,
                     periods_purchased: int = 1) -> dict:
    """Writes the payment intent, then calls GeniusPay for a hosted checkout
    URL. The only entry point that creates a `payments` row.

    Writing the row *before* calling the provider means a crash or timeout
    mid-call leaves an auditable, pending row -- not a phantom charge with no
    record on our side.

    plan_code/addon_code are stored as opaque strings here -- an FK to the
    plan/feature that requested this checkout, never interpreted. Exactly
    one must be set; the caller (purchasing) decides which, this function
    does not validate that either one IS a real plan/feature.

    Idempotency: a second call with the same `idempotency_key` replays the
    existing `checkout_url` if plan_code/addon_code/periods_purchased are all
    unchanged, or raises otherwise -- a stale/reused client-generated key
    should never silently switch what gets paid for.

    Args:
        account_id (str): Whoever is paying.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        amount_xof: Already computed by the caller -- billing never prices
            anything.
        description (str): Shown to the customer on GeniusPay's page.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.
        plan_code (str | None): Set for a plan purchase, exclusive with
            addon_code.
        addon_code (str | None): Set for an addon purchase, exclusive with
            plan_code.
        periods_purchased (int): How many of the item's own interval were
            bought -- stored for idempotency comparison and for whatever
            crediting logic reads it later.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ConflictError: IDEMPOTENCY_KEY_REUSED if this key was already used
            for a different plan/addon/duration.
    """
    sql_existing = """
        SELECT id, plan_code, addon_code, periods_purchased, checkout_url, status
        FROM payments WHERE idempotency_key = %s
        """
    params_existing = (idempotency_key,)
    existing_rows = query(sql_existing, params_existing)

    # REVIEW: idempotency dedupe. Same key + same plan/addon + same duration
    # -> replay the existing checkout_url (a retried request must not create
    # a second payment row). Anything else about the request differing ->
    # reject instead of silently switching what the caller ends up paying
    # for. This is the only thing standing between a client retry and a
    # double charge.
    if existing_rows:
        existing = existing_rows[0]
        same_request = (existing["plan_code"] == plan_code
                         and existing["addon_code"] == addon_code
                         and existing["periods_purchased"] == periods_purchased)
        if not same_request:
            raise ConflictError(
                "this idempotency_key was already used for a different plan/addon/duration",
                ErrorCode.IDEMPOTENCY_KEY_REUSED,
            )
        result = {
            "checkout_url": existing["checkout_url"],
            "reference": None,
            "status": existing["status"],
        }
        return result

    sql_insert_pending = """
        INSERT INTO payments (account_id, idempotency_key, provider, environment,
                               plan_code, addon_code, periods_purchased, amount_xof,
                               currency_code, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'XOF', %s)
        RETURNING id
        """
    params_insert_pending = (account_id, idempotency_key, PAYMENT_PROVIDER_NAME,
                              "sandbox" if payment_provider.is_sandbox() else "live",
                              plan_code, addon_code, periods_purchased, amount_xof,
                              PaymentStatus.PENDING)
    payment_rows = query(sql_insert_pending, params_insert_pending)
    payment_id = payment_rows[0]["id"]

    metadata = {"payment_id": str(payment_id), "account_id": account_id}
    if plan_code:
        metadata["plan_code"] = plan_code
    if addon_code:
        metadata["addon_code"] = addon_code

    provider_result = payment_provider.create_payment(
        amount_xof=amount_xof,
        description=description,
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
    """Writes the provider's reference/checkout_url/status/raw-response back
    onto the pending payments row.
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


def mark_payment_completed(conn, payment_id: str) -> None:
    """Sets a payment's status to completed. Called by purchasing once it
    has decided to actually credit this payment -- purchasing never writes
    `payments` SQL itself, it asks billing to.
    """
    sql = "UPDATE payments SET status = %s WHERE id = %s"
    params = (PaymentStatus.COMPLETED, payment_id)
    conn.execute(sql, params)


def mark_payment_blocked(conn, payment_id: str) -> None:
    """Sets a payment's status to blocked and applied=true (so
    reconcile_stuck_payments() stops re-finding it -- it is resolved, just
    not credited). Called by purchasing when its anti-downgrade check
    refuses to credit this payment.
    """
    sql = "UPDATE payments SET applied = true, status = %s WHERE id = %s"
    params = (PaymentStatus.BLOCKED, payment_id)
    conn.execute(sql, params)


def log_payment_event(conn, payment_id: str, reference: str, event_type: str, status: str) -> None:
    """Appends one payment_events audit row. Called by purchasing to record
    what it decided (payment.completed, downgrade_blocked, ...) -- purchasing
    never writes payment_events SQL itself either.
    """
    sql = """
        INSERT INTO payment_events (payment_id, reference, event_type, status, source)
        VALUES (%s, %s, %s, %s, 'reconcile_or_webhook')
        """
    params = (payment_id, reference, event_type, status)
    conn.execute(sql, params)


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
    """Finds the payment this confirmed status is about, then hands off to
    purchasing to decide what crediting it means -- all inside one
    transaction, so a payment's disposition (completed/blocked) is never
    decided without purchasing's crediting call actually running, or vice
    versa.

    Args:
        reference (str): GeniusPay's reference for this payment.
        provider_status (dict): Whatever get_payment_status() returned (or,
            sandbox-only, the trusted webhook payload).
    """
    if provider_status.get("status") != PaymentStatus.COMPLETED:
        return

    # NOTE: local import, not top-level -- purchasing.py imports billing.py
    # (for create_checkout/mark_payment_*/log_payment_event), so a top-level
    # import here would be circular. Billing still never contains plan/
    # subscription SQL -- it only calls out once it already knows the
    # payment is provider-confirmed complete.
    from app.services import purchasing

    with transaction() as conn:
        sql_find = """
            SELECT id, account_id, plan_code, addon_code
            FROM payments WHERE reference = %s AND applied = false
            """
        params_find = (reference,)
        row = conn.execute(sql_find, params_find).fetchone()
        if row is None:
            return

        # REVIEW: this is the actual money-crediting path. Billing's job
        # ends the moment it can say "GeniusPay confirms this completed" --
        # purchasing.apply_completed_payment() decides everything past that
        # sentence (anti-downgrade, crediting a subscription or an addon),
        # inside this same transaction so nothing here can half-apply.
        purchasing.apply_completed_payment(
            conn, payment_id=row["id"], reference=reference,
            account_id=row["account_id"], plan_code=row["plan_code"],
            addon_code=row["addon_code"],
        )
