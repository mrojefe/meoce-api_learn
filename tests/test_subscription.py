"""Guards the subscription-lookup service against the real database.

Integration, not unit: `get_subscription` reads `subscriptions`/`plans`
directly, so this needs a reachable database -- same reasoning as
`test_passwords.py`/`test_user_profile.py`.
"""

from datetime import datetime, timedelta, timezone

import pytest

from app.core.db.database import query
from app.services.subscription import get_subscription


@pytest.fixture
def existing_account():
    """A throwaway account, no subscription row yet -- cleaned up after."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]

    yield account_id

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def _insert_subscription(account_id: str, plan_code: str, status: str,
                          current_period_end: datetime | None) -> None:
    """Inserts one subscriptions row for the fixture account."""
    sql = """
        INSERT INTO subscriptions (account_id, plan_code, status, current_period_end)
        VALUES (%s, %s, %s, %s)
        """
    params = (account_id, plan_code, status, current_period_end)
    query(sql, params, nothing_return=True)


def test_get_subscription_falls_back_to_free_with_no_row(existing_account):
    """No subscriptions row at all -- same free-plan default every caller
    with no subscription gets."""
    result = get_subscription(existing_account)

    assert result["plan_code"] == "free"
    assert result["status"] == "active"
    assert result["current_period_end"] is None


def test_get_subscription_returns_a_real_active_plan(existing_account):
    """An active, non-expired row is returned as-is, not the free default."""
    _insert_subscription(existing_account, "premium", "active", None)

    result = get_subscription(existing_account)

    assert result["plan_code"] == "premium"
    assert result["status"] == "active"


def test_get_subscription_ignores_an_expired_active_row(existing_account):
    """A row marked active whose current_period_end already passed must
    NOT count -- the exact bug this service's docstring documents as
    measured/real (four such rows found on staging 2026-09-02)."""
    expired_at = datetime.now(timezone.utc) - timedelta(days=1)
    _insert_subscription(existing_account, "premium", "active", expired_at)

    result = get_subscription(existing_account)

    assert result["plan_code"] == "free"
