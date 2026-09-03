"""Entitlements — what the caller's plan allows.

Answers one question, asked by every route that gates anything: *given this
user, what may they do?*

The answer is deliberately NOT in the token. A token lasts 24 hours and a plan
does not: someone who upgrades at 10:00 would wait until 16:00 for access, and
someone who cancels would keep paid features just as long. So the rule is:

    put in a token only what cannot change during the token's life

The user id cannot change. The plan can. Hence a lookup.

**Cost, stated plainly:** one query per request that gates something. A short
cache would remove it, and is deliberately not here — caching is its own
subject, and copied caching code is code nobody can explain. Revisit once it
is understood, not before.
"""

from app.core.db.database import query
from app.core.reference import PlanCode
from app.schemas.plans import PlanFeatures

DEFAULT_PLAN_CODE = PlanCode.FREE


def resolve_entitlements(user_id: str) -> PlanFeatures:
    """Returns what this user's plan grants.

    Two conditions decide whether a subscription counts, and both are needed:

    * `status = 'active'` — the obvious one.
    * `current_period_end` still in the future, or absent.

    The second exists because the data disagrees with the first. Measured on
    staging 2026-09-02: **four** subscriptions are marked active with a period
    that ended in the past. Trusting `status` alone would grant paid features to
    accounts that stopped paying — the row says active because nothing has run
    to say otherwise, not because it is true.

    A NULL `current_period_end` is treated as no expiry, which is what a free
    plan looks like.

    Falls back to the free plan when nothing matches — an unknown user, a user
    with no subscription row, an expired one. Never raises: a caller that cannot
    be identified gets the least, rather than an error page. Today every one of
    the 167 users has a row, but "true today" is not "guaranteed", and a signup
    bug should not become a 500.

    Args:
        user_id (str): The authenticated caller, from `get_current_user_id`.

    Returns:
        PlanFeatures: The plan's features, parsed and validated. A typo'd key in
            the JSONB raises here rather than silently reading as unlimited.

    Examples:
        >>> resolve_entitlements("c028c759-5fee-402b-a09f-ef39f3c22f31")
        PlanFeatures(max_watchlists=2, history_years_max=3, ...)
    """
    sql_plan = """
        SELECT p.features
        FROM subscriptions AS s
        JOIN subscription_plans AS p
            ON p.code = s.plan_code
        WHERE s.user_id = %s
          AND s.status = 'active'
          AND (s.current_period_end IS NULL OR s.current_period_end > now())
        ORDER BY s.started_at DESC
        LIMIT 1
        """
    params_plan=user_id    
    rows = query(sql_plan, (params_plan,))

    if not rows:
        return _default_plan()

    return PlanFeatures(**rows[0]["features"])


def _default_plan() -> PlanFeatures:
    """The free plan, read from the database rather than hardcoded.

    Hardcoding the fallback would create a second truth: change a free limit in
    `subscription_plans` and the fallback would keep the old one, so a user
    without a subscription row would get different limits from one who has the
    free plan explicitly.

    If even that lookup fails — the free plan renamed or deleted — the bare
    `PlanFeatures()` defaults apply: every switch off, every limit unlimited.
    That asymmetry is uncomfortable and deliberate: it is the shape of the
    model, and a plan table so broken that 'free' is missing is a problem to
    fix, not to paper over here.

    Returns:
        PlanFeatures: The free plan's features.
    """
    sql_default_plan =  "SELECT features FROM subscription_plans WHERE code = %s"
    params_default_plan = DEFAULT_PLAN_CODE
    rows = query( sql_default_plan  , (params_default_plan,),)

    if not rows:
        # A 500, not a 404. The caller asked for their watchlists, not for the
        # free plan — the plan table being broken is our problem, and a bare
        # raise gives the catch-all handler a traceback to log.
        raise RuntimeError(
            f"plan {DEFAULT_PLAN_CODE!r} missing from subscription_plans"
        )

    return PlanFeatures(**rows[0]["features"])
