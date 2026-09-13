"""Guards the entitlements-resolution service against the real database.

Integration, not unit: `resolve_entitlements` reads `subscriptions`/
`plan_features`/`user_features` directly, so this needs a reachable
database -- same reasoning as `test_subscription.py`.
"""


import pytest

from app.core.db.database import query
from app.services.entitlements import resolve_entitlements


@pytest.fixture
def existing_account():
    """A throwaway account, no subscription/grants yet -- cleaned up after."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]

    yield account_id

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def test_resolve_entitlements_falls_back_to_free_plan(existing_account):
    """No subscription row -- the caller gets the free plan's real
    features, read from plan_features, not a hardcoded fallback."""
    result = resolve_entitlements(existing_account)

    # free plan's own real, live values -- confirmed against meoce_prod
    # before writing this test, not guessed.
    assert result.max_watchlists == 2
    assert result.history_years_max == 3
    assert result.news_feed is True
    assert result.pro_chart_types is False


def test_resolve_entitlements_uses_a_real_active_subscription(existing_account):
    """An active subscription's plan_features values show up in the
    returned PlanFeatures, not the free plan's."""
    sql = "INSERT INTO subscriptions (account_id, plan_code, status) VALUES (%s, 'premium', 'active')"
    params = (existing_account,)
    query(sql, params, nothing_return=True)

    result = resolve_entitlements(existing_account)

    assert result.custom_timeframes is True
    assert result.history_years_max is None  # premium: unlimited


def test_resolve_entitlements_grant_overrides_the_plan_value(existing_account):
    """A user_features grant wins for its one key; every other key still
    comes from the plan -- the "à-la-carte layer" the docstring describes."""
    sql = "INSERT INTO user_features (account_id, feature_key, value) VALUES (%s, 'max_watchlists', %s)"
    params = (existing_account, "10")
    query(sql, params, nothing_return=True)

    result = resolve_entitlements(existing_account)

    assert result.max_watchlists == 10  # the grant, not free's 2
    assert result.history_years_max == 3  # untouched, still free's value
