"""Purchasing -- what buying a plan, a custom plan, or an addon MEANS.

Prices a purchase, gates it (the anti-downgrade check), builds custom plans,
and -- only after billing.py has confirmed GeniusPay says a payment
completed -- credits it: extends a subscription's period and refreshes its
feature snapshot, or extends a standalone addon's expiry.

This is the split billing.py used to be responsible for. Per JF: billing
must be the money-taking mechanic ONLY; everything about what a plan/
feature/subscription/custom-plan IS belongs here instead. This module reads
and writes `plans`/`plan_features`/`subscriptions`/`subscription_features`/
`user_features`/`features` -- billing.py never does. Where this module needs
to record something about the `payments`/`payment_events` tables (mark a
payment completed/blocked, log an event), it calls billing's own small
helpers rather than writing that SQL itself -- billing keeps sole ownership
of its own tables' SQL text.
"""

import secrets

from psycopg.types.json import Jsonb

from app.core.db.database import query, transaction
from app.core.errors import ApiError, ErrorCode, ErrorStatus
from app.services import billing


def price_plan_purchase(plan_code: str, periods_purchased: int, user_id: str) -> dict:
    """Looks up a plan's real price and validates it is purchasable by this
    caller. The only place `amount_xof` for a plan purchase is computed --
    billing.create_checkout() receives the result, never derives this itself.

    Args:
        plan_code (str): Must be an active, priced plan. If it is a custom
            plan (kind='custom'), the caller must own it -- checked against
            the DB, not just PlanCode, since custom codes are never in that
            enum by design.
        periods_purchased (int): How many of the plan's own interval to buy.
        user_id (str): The caller -- checked against a custom plan's owner.

    Returns:
        dict: amount_xof, description -- everything
            billing.create_checkout() needs.

    Raises:
        ApiError: PLAN_NOT_FOUND if plan_code is not an active, priced plan,
            or belongs to a different account.
    """
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
    result = {"amount_xof": amount_xof, "description": f"MEOCE -- {plan['name']} x{periods_purchased}"}
    return result


def price_addon_purchase(feature_key: str, periods_purchased: int) -> dict:
    """Looks up a feature's real price and validates it is purchasable as a
    standalone addon.

    Args:
        feature_key (str): Must be an active, priced, boolean-kind feature --
            a limit-kind feature has no unambiguous purchased value (what
            number would it grant?), so it is not purchasable here.
        periods_purchased (int): How many of the feature's own interval to
            buy.

    Returns:
        dict: amount_xof, description.

    Raises:
        ApiError: PLAN_NOT_FOUND if feature_key is not a purchasable addon
            (reused code -- "the thing you asked to buy doesn't exist" reads
            the same whether it's a plan or a feature).
    """
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
    result = {"amount_xof": amount_xof, "description": f"MEOCE -- {feature['label']} x{periods_purchased}"}
    return result


def checkout_plan(user_id: str, plan_code: str, periods_purchased: int,
                   idempotency_key: str, success_url: str, error_url: str) -> dict:
    """Prices a plan purchase, then hands off to billing to actually take
    the money.

    Args:
        user_id (str): The authenticated caller.
        plan_code (str): See price_plan_purchase().
        periods_purchased (int): How many of the plan's own interval to buy,
            chosen by the user.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ApiError: VALIDATION if periods_purchased is out of billing's sane
            range. PLAN_NOT_FOUND -- see price_plan_purchase().
        ConflictError: IDEMPOTENCY_KEY_REUSED -- see billing.create_checkout().
    """
    _validate_periods_purchased(periods_purchased)
    priced = price_plan_purchase(plan_code, periods_purchased, user_id)

    return billing.create_checkout(
        account_id=user_id, idempotency_key=idempotency_key,
        amount_xof=priced["amount_xof"], description=priced["description"],
        success_url=success_url, error_url=error_url,
        plan_code=plan_code, periods_purchased=periods_purchased,
    )


def checkout_addon(user_id: str, feature_key: str, periods_purchased: int,
                    idempotency_key: str, success_url: str, error_url: str) -> dict:
    """Prices a standalone addon purchase, then hands off to billing to
    actually take the money. Independent of plan state, any time.

    Args:
        user_id (str): The authenticated caller.
        feature_key (str): See price_addon_purchase().
        periods_purchased (int): How many of the feature's own interval to
            buy.
        idempotency_key (str): Client-generated, unique per checkout attempt.
        success_url (str): Where GeniusPay sends the browser back on success.
        error_url (str): Where GeniusPay sends the browser back on failure.

    Returns:
        dict: checkout_url, reference, status.

    Raises:
        ApiError: VALIDATION if periods_purchased is out of billing's sane
            range. PLAN_NOT_FOUND -- see price_addon_purchase().
        ConflictError: IDEMPOTENCY_KEY_REUSED -- see billing.create_checkout().
    """
    _validate_periods_purchased(periods_purchased)
    priced = price_addon_purchase(feature_key, periods_purchased)

    return billing.create_checkout(
        account_id=user_id, idempotency_key=idempotency_key,
        amount_xof=priced["amount_xof"], description=priced["description"],
        success_url=success_url, error_url=error_url,
        addon_code=feature_key, periods_purchased=periods_purchased,
    )


def _validate_periods_purchased(periods_purchased: int) -> None:
    """Raises if periods_purchased is outside the sane range. Shared by
    checkout_plan()/checkout_addon() -- same rule, same message, one place
    to change the bound.
    """
    if not (billing.MIN_PERIODS_PURCHASED <= periods_purchased <= billing.MAX_PERIODS_PURCHASED):
        raise ApiError(
            ErrorCode.VALIDATION,
            f"periods_purchased must be between {billing.MIN_PERIODS_PURCHASED} and "
            f"{billing.MAX_PERIODS_PURCHASED}, got {periods_purchased!r}",
            ErrorStatus.UNPROCESSABLE_ENTITY,
        )


def create_custom_plan(user_id: str, feature_keys: list[str]) -> str:
    """Builds a user's own custom plan: a new `plans` row (kind='custom',
    owner_account_id=user_id) priced as the sum of the chosen features'
    price_xof, computed once and stored -- never recomputed live. The
    returned plan_code is then bought like any other plan, via
    checkout_plan().

    Scoped to boolean-kind features only -- same reasoning as
    price_addon_purchase(): a limit-kind feature has no single purchased
    value to grant.

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


def apply_completed_payment(conn, payment_id: str, reference: str, account_id: str,
                             plan_code: str | None, addon_code: str | None) -> None:
    """Decides what a provider-confirmed-completed payment causes, and does
    it. Called by billing._apply_verified_status() only after GeniusPay
    itself has confirmed the payment completed -- this function trusts that
    much, but re-decides everything about what it MEANS (anti-downgrade,
    crediting) itself.

    Runs inside the caller's already-open transaction -- billing owns when
    the transaction starts/ends, purchasing just writes into it, so a
    payment's recorded outcome and its actual credit can never land only
    one of the two.

    Args:
        conn: The live psycopg connection, from billing's transaction().
        payment_id (str): The payments row this is about.
        reference (str): GeniusPay's reference, for the audit event.
        account_id (str): Who is being credited.
        plan_code (str | None): Set for a plan purchase.
        addon_code (str | None): Set for an addon purchase. Exactly one of
            plan_code/addon_code is set, matching the payments table's own
            CHECK constraint.
    """
    if addon_code is not None:
        _credit_addon(conn, payment_id, reference)
    else:
        _credit_plan(conn, payment_id, reference, account_id, plan_code)


def _credit_plan(conn, payment_id: str, reference: str, account_id: str, plan_code: str) -> None:
    """The plan-purchase half of apply_completed_payment(): the
    anti-downgrade check, then either block or credit.
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
            billing.mark_payment_blocked(conn, payment_id)
            billing.log_payment_event(conn, payment_id, reference, "downgrade_blocked", billing.PaymentStatus.BLOCKED)
            return

    billing.mark_payment_completed(conn, payment_id)

    sql_apply = "SELECT apply_payment_to_subscription(%s)"
    params_apply = (payment_id,)
    conn.execute(sql_apply, params_apply)

    billing.log_payment_event(conn, payment_id, reference, "payment.completed", billing.PaymentStatus.COMPLETED)


def _credit_addon(conn, payment_id: str, reference: str) -> None:
    """The addon-purchase half of apply_completed_payment(): no
    anti-downgrade check (addons are independent of plan state, per the
    design), straight to crediting.
    """
    billing.mark_payment_completed(conn, payment_id)

    sql_apply = "SELECT apply_payment_to_addon(%s)"
    params_apply = (payment_id,)
    conn.execute(sql_apply, params_apply)

    billing.log_payment_event(conn, payment_id, reference, "payment.completed", billing.PaymentStatus.COMPLETED)
