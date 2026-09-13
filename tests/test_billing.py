"""Guards billing's checkout/idempotency/custom-plan logic against the real
database.

Integration for the database side (payments/plans/features rows), same
reasoning as test_subscription.py -- but the actual GeniusPay HTTP call is
mocked: hitting their real sandbox on every test run is slow and makes the
suite depend on network + a third party being up. What is real here -- the
idempotency dedupe, the amount_xof formula, custom-plan creation, and the
anti-downgrade check -- is exactly the part this codebase newly wrote; the
provider call itself is proven separately (app/services/payment_provider.py
is a thin, directly-verified wire client).
"""

from unittest.mock import patch

import pytest

from app.core.db.database import query
from app.core.errors import ApiError, ConflictError
from app.services.billing import checkout_addon, checkout_plan, create_custom_plan
from app.services.plans import list_features, list_plans

FAKE_PROVIDER_RESULT = {
    "reference": "SANDBOX-TEST-REF",
    "checkout_url": "https://geniuspay.ci/checkout/test",
    "status": "pending",
    "amount": 8500,
    "raw": {"success": True},
}


@pytest.fixture
def existing_account():
    """A throwaway account -- cleaned up after, cascades to payments/
    subscriptions/user_features rows."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]

    yield account_id

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


@pytest.fixture
def purchasable_feature():
    """A throwaway boolean, priced, active feature -- so addon/custom-plan
    tests do not depend on real catalog rows staying priced at 0 forever."""
    key = "test_addon_feature"
    sql_insert = """
        INSERT INTO features (key, label, kind, free_default, price_xof, interval, interval_count, is_active)
        VALUES (%s, 'Test addon', 'boolean', 'false', 1000, 'week', 1, true)
        ON CONFLICT (key) DO UPDATE SET price_xof = 1000, is_active = true
        """
    query(sql_insert, (key,), nothing_return=True)

    yield key

    # Delete any payments row created against this feature first -- a test
    # account's teardown may already be gone (cascade), or may run after
    # this one depending on fixture order, so this delete must not assume
    # which happened first.
    query("DELETE FROM payments WHERE addon_code = %s", (key,), nothing_return=True)
    query("DELETE FROM features WHERE key = %s", (key,), nothing_return=True)


def test_list_plans_only_returns_fixed_plans():
    """A custom plan (kind='custom') must never leak into the public
    picker -- the bug the old, filterless list_plans() had."""
    plans = list_plans()

    codes = {plan.code for plan in plans}
    assert "free" in codes
    assert "plus" in codes
    assert all(not code.startswith("custom_") for code in codes)


def test_list_features_only_returns_priced_boolean_features(purchasable_feature):
    features = list_features()

    keys = {row["key"] for row in features}
    assert purchasable_feature in keys


def test_checkout_plan_rejects_unknown_plan(existing_account):
    with pytest.raises(ApiError):
        checkout_plan(existing_account, "not_a_real_plan", 1, "key-1",
                       "https://example.com/ok", "https://example.com/fail")


def test_checkout_plan_rejects_out_of_range_periods(existing_account):
    with pytest.raises(ApiError):
        checkout_plan(existing_account, "plus", 0, "key-1a",
                       "https://example.com/ok", "https://example.com/fail")


@patch("app.services.payment_provider.create_payment")
def test_checkout_plan_computes_amount_from_periods(mock_create_payment, existing_account):
    mock_create_payment.return_value = FAKE_PROVIDER_RESULT

    checkout_plan(existing_account, "plus", 3, "key-2",
                  "https://example.com/ok", "https://example.com/fail")

    call_kwargs = mock_create_payment.call_args.kwargs
    # plus is 8500 XOF/month, interval_count=1 -> 3 periods = 25500
    assert call_kwargs["amount_xof"] == 8500 * 1 * 3


@patch("app.services.payment_provider.create_payment")
def test_checkout_plan_replays_same_key_same_plan_and_duration(mock_create_payment, existing_account):
    mock_create_payment.return_value = FAKE_PROVIDER_RESULT

    first = checkout_plan(existing_account, "plus", 1, "key-3",
                           "https://example.com/ok", "https://example.com/fail")
    second = checkout_plan(existing_account, "plus", 1, "key-3",
                            "https://example.com/ok", "https://example.com/fail")

    assert first["checkout_url"] == second["checkout_url"]
    mock_create_payment.assert_called_once()


@patch("app.services.payment_provider.create_payment")
def test_checkout_plan_rejects_key_reused_for_a_different_duration(mock_create_payment, existing_account):
    mock_create_payment.return_value = FAKE_PROVIDER_RESULT
    checkout_plan(existing_account, "plus", 1, "key-4",
                  "https://example.com/ok", "https://example.com/fail")

    with pytest.raises(ConflictError):
        checkout_plan(existing_account, "plus", 2, "key-4",
                       "https://example.com/ok", "https://example.com/fail")


@patch("app.services.payment_provider.create_payment")
def test_checkout_addon_rejects_unpriced_feature(mock_create_payment, existing_account):
    with pytest.raises(ApiError):
        checkout_addon(existing_account, "news_feed", 1, "key-5",
                        "https://example.com/ok", "https://example.com/fail")
    mock_create_payment.assert_not_called()


@patch("app.services.payment_provider.create_payment")
def test_checkout_addon_writes_addon_code_not_plan_code(mock_create_payment, existing_account,
                                                         purchasable_feature):
    mock_create_payment.return_value = FAKE_PROVIDER_RESULT

    checkout_addon(existing_account, purchasable_feature, 2, "key-6",
                   "https://example.com/ok", "https://example.com/fail")

    sql = "SELECT plan_code, addon_code, amount_xof FROM payments WHERE idempotency_key = %s"
    row = query(sql, ("key-6",))[0]
    assert row["plan_code"] is None
    assert row["addon_code"] == purchasable_feature
    assert row["amount_xof"] == 1000 * 1 * 2


def test_create_custom_plan_rejects_empty_feature_list(existing_account):
    with pytest.raises(ApiError):
        create_custom_plan(existing_account, [])


def test_create_custom_plan_rejects_unpurchasable_feature(existing_account):
    with pytest.raises(ApiError):
        create_custom_plan(existing_account, ["news_feed"])  # priced at 0, not purchasable


def test_create_custom_plan_sums_prices_and_stores_owner(existing_account, purchasable_feature):
    plan_code = create_custom_plan(existing_account, [purchasable_feature])

    try:
        sql_plan = "SELECT kind, owner_account_id, price_xof FROM plans WHERE code = %s"
        plan = query(sql_plan, (plan_code,))[0]
        assert plan["kind"] == "custom"
        assert str(plan["owner_account_id"]) == str(existing_account)
        assert plan["price_xof"] == 1000

        sql_features = "SELECT feature_key FROM plan_features WHERE plan_code = %s"
        feature_keys = {row["feature_key"] for row in query(sql_features, (plan_code,))}
        assert feature_keys == {purchasable_feature}
    finally:
        query("DELETE FROM plans WHERE code = %s", (plan_code,), nothing_return=True)


@patch("app.services.payment_provider.create_payment")
def test_checkout_plan_rejects_someone_elses_custom_plan(mock_create_payment, existing_account,
                                                          purchasable_feature):
    other_account = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    plan_code = create_custom_plan(other_account, [purchasable_feature])

    try:
        with pytest.raises(ApiError):
            checkout_plan(existing_account, plan_code, 1, "key-7",
                           "https://example.com/ok", "https://example.com/fail")
        mock_create_payment.assert_not_called()
    finally:
        query("DELETE FROM plans WHERE code = %s", (plan_code,), nothing_return=True)
        query("DELETE FROM accounts WHERE id = %s", (other_account,), nothing_return=True)
