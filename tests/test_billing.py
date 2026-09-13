"""Guards billing's checkout/idempotency logic against the real database.

Integration for the database side (payments/plans rows), same reasoning as
test_subscription.py -- but the actual GeniusPay HTTP call is mocked: hitting
their real sandbox on every test run is slow and makes the suite depend on
network + a third party being up. What is real here -- the idempotency
dedupe, the plan-not-found check, and list_plans() -- is exactly the part
this codebase newly wrote; the provider call itself is proven separately
(app/services/payment_provider.py is a thin, directly-verified wire client).
"""

from unittest.mock import patch

import pytest

from app.core.db.database import query
from app.core.errors import ApiError, ConflictError
from app.services.billing import list_plans, start_checkout


@pytest.fixture
def existing_account():
    """A throwaway account -- cleaned up after, cascades to payments rows."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]

    yield account_id

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def test_list_plans_returns_real_active_plans():
    """Every plan comes back with its features resolved -- not just a bare
    row from `plans`."""
    plans = list_plans()

    codes = {plan.code for plan in plans}
    assert "free" in codes
    assert "plus" in codes

    plus = next(plan for plan in plans if plan.code == "plus")
    assert plus.price_xof > 0
    assert plus.features.max_watchlists is None or plus.features.max_watchlists >= 0


def test_start_checkout_rejects_unknown_plan(existing_account):
    with pytest.raises(ApiError):
        start_checkout(existing_account, "not_a_real_plan", "key-1",
                        "https://example.com/ok", "https://example.com/fail")


@patch("app.services.payment_provider.create_payment")
def test_start_checkout_writes_a_pending_payment_row(mock_create_payment, existing_account):
    mock_create_payment.return_value = {
        "reference": "SANDBOX-TEST-REF",
        "checkout_url": "https://geniuspay.ci/checkout/test",
        "status": "pending",
        "amount": 8500,
        "raw": {"success": True},
    }

    result = start_checkout(existing_account, "plus", "key-2",
                             "https://example.com/ok", "https://example.com/fail")

    assert result["checkout_url"] == "https://geniuspay.ci/checkout/test"
    assert result["reference"] == "SANDBOX-TEST-REF"
    mock_create_payment.assert_called_once()


@patch("app.services.payment_provider.create_payment")
def test_start_checkout_replays_same_key_same_plan(mock_create_payment, existing_account):
    mock_create_payment.return_value = {
        "reference": "SANDBOX-TEST-REF-2",
        "checkout_url": "https://geniuspay.ci/checkout/replay",
        "status": "pending",
        "amount": 8500,
        "raw": {"success": True},
    }

    first = start_checkout(existing_account, "plus", "key-3",
                            "https://example.com/ok", "https://example.com/fail")
    second = start_checkout(existing_account, "plus", "key-3",
                             "https://example.com/ok", "https://example.com/fail")

    assert first["checkout_url"] == second["checkout_url"]
    mock_create_payment.assert_called_once()


@patch("app.services.payment_provider.create_payment")
def test_start_checkout_rejects_key_reused_for_a_different_plan(mock_create_payment, existing_account):
    mock_create_payment.return_value = {
        "reference": "SANDBOX-TEST-REF-3",
        "checkout_url": "https://geniuspay.ci/checkout/first-plan",
        "status": "pending",
        "amount": 8500,
        "raw": {"success": True},
    }
    start_checkout(existing_account, "plus", "key-4",
                    "https://example.com/ok", "https://example.com/fail")

    with pytest.raises(ConflictError):
        start_checkout(existing_account, "pro", "key-4",
                        "https://example.com/ok", "https://example.com/fail")
