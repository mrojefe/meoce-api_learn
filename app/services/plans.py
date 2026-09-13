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
    """Every active, purchasable feature (the addon picker's catalog) --
    boolean-kind and limit-kind alike.

    `plan_features.value`/`user_features.value` are jsonb; they already
    store any value, proven by every existing limit-kind plan_features row
    (e.g. plus/pro's max_watchlists=null). The real, narrower gap was never
    "nowhere to store a purchased value" -- it was that nothing stated
    *what number* a purchase should grant. Fixed by migration
    20260913030000_add_purchase_grant_value_to_features.sql: a real,
    bounded integer per limit-kind feature (never null/unlimited -- see
    purchasing.create_custom_plan()/apply_payment_to_addon() for where it's
    consumed).

    Returns:
        list[dict]: key, label, description, price_xof, interval,
            interval_count, purchase_grant_value -- everything the addon
            picker needs to display and buy one. purchase_grant_value is
            always None here for a boolean-kind row (unused, the grant is
            unambiguously true).
    """
    sql_features = """
        SELECT key, label, description, price_xof, interval, interval_count,
               purchase_grant_value
        FROM features
        WHERE is_active = true AND price_xof > 0
        ORDER BY display_order
        """
    rows = query(sql_features)

    return rows
