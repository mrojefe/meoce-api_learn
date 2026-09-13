"""The caller's own subscription — what they're actually paying for.

    Distinct from `entitlements`: this answers "what am I subscribed to right
    now" (plan, status, when it ends), not "what am I allowed to do."
"""

from app.core.db.database import query
from app.core.reference import PlanCode

DEFAULT_PLAN_CODE = PlanCode.FREE


def get_subscription(user_id: str) -> dict:
    """Returns the caller's active subscription, or the free plan if none.

        Same expiry rule as `resolve_entitlements`: a row marked `active` with
        a `current_period_end` already in the past does not count.
        `expire_due_subscriptions()` exists in the database but nothing calls
        it yet (task #34), so stale rows are common today.

        Args:
            user_id (str): The authenticated caller.

        Returns:
            dict: plan_code, plan_name, status, current_period_end.
    """
    # NOTE: subscriptions' real column is account_id, not user_id -- kept
    # named user_id on the Python side to match the codebase-wide
    # convention (JWT claim, get_current_user_id(), ~350 other call sites).
    sql = """
        SELECT s.plan_code, p.name AS plan_name, s.status, s.current_period_end
        FROM subscriptions AS s
        JOIN plans AS p ON p.code = s.plan_code
        WHERE s.account_id = %s
          AND s.status = 'active'
          AND (s.current_period_end IS NULL OR s.current_period_end > now())
        """
    params = (user_id,)
    rows = query(sql, params)

    if rows:
        return dict(rows[0])

    return _default_subscription()


def _default_subscription() -> dict:
    """The free plan's identity, for a caller with no active subscription."""
    sql = "SELECT code AS plan_code, name AS plan_name FROM plans WHERE code = %s"
    params = (DEFAULT_PLAN_CODE,)
    rows = query(sql, params)

    if not rows:
        raise RuntimeError(f"plan {DEFAULT_PLAN_CODE!r} has no row in plans")

    return {**rows[0], "status": "active", "current_period_end": None}
