"""Plans and features catalog -- public, read-only, no money involved.

Split out of billing.py: JF's own words -- "billing part must be the stuff
who take the money" -- and list_plans()/list_features() are pure catalog
reads with no auth, no payment. Kept as its own module so billing.py stays
exactly the checkout/webhook/reconcile orchestration and nothing else.
"""

from app.core.db.database import query
from app.schemas.plans import Plan, PlanFeatures


def list_plans() -> list[Plan]:
    """Every active, FIXED plan, priced and with its features, for the
    frontend's plan-picker.

    `kind = 'fixed'` is an explicit filter, not an oversight: a user's own
    custom plan (kind='custom', created via billing.create_custom_plan) also
    lives in this same `plans` table -- without this filter it would leak
    into the public picker every other caller sees.

    Returns:
        list[Plan]: Ordered by `display_order`, the same order the plans
            table itself defines for presentation.
    """
    sql_plans = """
        SELECT code, name, price_xof, interval, interval_count
        FROM plans
        WHERE is_active = true AND kind = 'fixed'
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


def list_features() -> list[dict]:
    """Every active, purchasable feature (the addon picker's catalog).

    Scoped to boolean-kind features only: `features` has no column stating
    what value a *purchased* limit-kind feature should grant (buying
    max_watchlists -- grant what number?). Only a boolean has one
    unambiguous purchased value (true), so a limit-kind feature is not
    purchasable until the schema gains a column for that -- not invented
    here.

    Returns:
        list[dict]: key, label, description, price_xof, interval,
            interval_count -- everything the addon picker needs to display
            and buy one.
    """
    sql_features = """
        SELECT key, label, description, price_xof, interval, interval_count
        FROM features
        WHERE is_active = true AND kind = 'boolean' AND price_xof > 0
        ORDER BY display_order
        """
    return query(sql_features)
