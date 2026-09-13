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
    """Returns what this user is actually entitled to: their plan, with any
        individual grants layered on top.

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

        On top of the plan, individual `user_features` grants win per key — the
        à-la-carte layer, same rule as the real API's `get_user_entitlements()` SQL
        function: a non-expired grant for a feature overrides whatever the plan
        says for that one feature, and every other key keeps its plan value.

        Args:
            user_id (str): The authenticated caller, from `get_current_user_id`.

        Returns:
            PlanFeatures: The plan's features, with any individual grants applied,
                parsed and validated. A typo'd key in the JSONB raises here rather
                than silently reading as unlimited.

        Examples:
            >>> resolve_entitlements("c028c759-5fee-402b-a09f-ef39f3c22f31")
            PlanFeatures(max_watchlists=2, history_years_max=3, ...)
    """
    # NOTE: subscriptions' real column is account_id, not user_id -- kept
    # named user_id on the Python side to match the codebase-wide
    # convention (JWT claim, get_current_user_id(), ~350 other call sites).
    #
    # Reads subscription_features -- a SNAPSHOT taken by
    # apply_payment_to_subscription() at the moment this subscription was
    # last paid for -- not a live join to plan_features. If plan_features
    # changes later (an admin edits a plan's limits), an existing paying
    # subscriber keeps what they actually bought until their next payment
    # refreshes the snapshot; a live join would have changed it retroactively.
    sql_plan = """
        SELECT sf.feature_key, sf.value_snapshot AS value
        FROM subscriptions AS s
        JOIN subscription_features AS sf
            ON sf.subscription_id = s.id
        WHERE s.account_id = %s
          AND s.status = 'active'
          AND (s.current_period_end IS NULL OR s.current_period_end > now())
        """
    params_plan = (user_id,)
    rows = query(sql_plan, params_plan)

    if rows:
        plan = {row["feature_key"]: row["value"] for row in rows}
        plan = {**_default_plan_features(), **plan}
    else:
        plan = _default_plan_features()

    merged = {**plan, **_active_grants(user_id)}

    return PlanFeatures(**merged)


def _active_grants(user_id: str) -> dict:
    """The caller's individual `user_features` grants, one value per key.

        A user can hold more than one grant for the same feature (the primary
        key is `(user_id, feature_key, source)` — see the payment/subscription
        Miro diagram) — an addon and a support-team override could both exist
        at once. `DISTINCT ON` picks exactly one per `feature_key`, the most
        recently granted, same tie-break the real API's SQL function uses.

        Args:
            user_id (str): The authenticated caller.

        Returns:
            dict: feature_key -> value, non-expired grants only. Empty if the
                caller has none — true for everyone today, `user_features` is
                unused in staging.
    """
    # NOTE: user_features' real column is account_id, not user_id -- kept
    # named user_id on the Python side to match the codebase-wide
    # convention (JWT claim, get_current_user_id(), ~350 other call sites).
    sql_grants = """
                    SELECT DISTINCT ON (feature_key) feature_key, value
                    FROM user_features
                    WHERE account_id = %s
                    AND (expires_at IS NULL OR expires_at > now())
                    ORDER BY feature_key, granted_at DESC
                """
    params_grants = (user_id,)
    rows = query(sql_grants, params_grants)

    current_user_all_available_addon = {row["feature_key"]: row["value"] for row in rows}
    return current_user_all_available_addon


def _default_plan_features() -> dict:
    """The free plan's raw features dict, read from the database rather than
        hardcoded.

        Hardcoding the fallback would create a second truth: change a free
        limit in `subscription_plans` and the fallback would keep the old one,
        so a user without a subscription row would get different limits from
        one who has the free plan explicitly.

        Returns a dict, not `PlanFeatures`: `resolve_entitlements` still needs
        to merge this with any individual grants before building the final,
        validated `PlanFeatures` once, at the end.

        Returns:
            dict: The free plan's features, as stored — not yet validated.

        Raises:
            RuntimeError: The free plan itself is missing from
                `subscription_plans` — a 500, not a fallback. The caller asked
                for their entitlements, not for the free plan; a plan table
                this broken is our problem, not something to paper over here.
    """
    sql_default_plan = "SELECT feature_key, value FROM plan_features WHERE plan_code = %s"
    params_default_plan = (DEFAULT_PLAN_CODE,)
    rows = query(sql_default_plan, params_default_plan)

    if not rows:
        raise RuntimeError(
            f"plan {DEFAULT_PLAN_CODE!r} has no rows in plan_features"
        )

    return {row["feature_key"]: row["value"] for row in rows}
