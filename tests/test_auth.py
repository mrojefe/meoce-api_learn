"""Guards login/signup/refresh against the real database and Redis."""

import uuid
from unittest.mock import Mock

import pytest

from app.core.db.database import query
from app.core.db.redis import get_redis
from app.core.errors import ConflictError, RateLimitError, UnauthorizedError
from app.core.security.deps.passwords import hash_password
from app.services.auth import (
    login,
    logout,
    refresh_access_token,
    request_password_reset,
    reset_password,
    signup,
)

TEST_PASSWORD = "TestPass123!"


@pytest.fixture
def fake_request():
    """A Request stand-in for the rate-limit IP lookup and _decode logging.

    Always resolves to the same "unknown" IP (no client, no forwarded
    header), so its own rate-limit key is cleaned before and after every
    test that uses it — otherwise tests accumulate the same counter and
    a later one gets rate-limited instead of testing what it's supposed to.
    """
    request = Mock()
    request.headers = {}
    request.client = None

    get_redis().delete("signup:unknown")
    get_redis().delete("refresh:unknown")

    yield request

    get_redis().delete("signup:unknown")
    get_redis().delete("refresh:unknown")


@pytest.fixture
def existing_user():
    """A throwaway, already-verified account, cleaned up after.

    NOTE: identity schema is accounts (root) + user_identities (one row
    per login method) -- not a flat users table.
    """
    email = f"test-auth-{uuid.uuid4()}@example.com"
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, credential, verified) "
        "VALUES (%s, 'email', %s, %s, true)",
        (account_id, email, hash_password(TEST_PASSWORD)),
        nothing_return=True,
    )
    get_redis().delete(f"login:{email}")

    yield email

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)
    get_redis().delete(f"login:{email}")


def test_login_returns_a_working_token_pair(existing_user):
    result = login(existing_user, TEST_PASSWORD)
    assert "access_token" in result
    assert "refresh_token" in result


def test_login_rejects_wrong_password(existing_user):
    with pytest.raises(UnauthorizedError):
        login(existing_user, "WrongPassword1!")


def test_login_rate_limited_after_five_attempts(existing_user):
    for _ in range(5):
        with pytest.raises(UnauthorizedError):
            login(existing_user, "WrongPassword1!")

    with pytest.raises(RateLimitError):
        login(existing_user, "WrongPassword1!")


def test_signup_creates_an_account(fake_request):
    email = f"test-signup-{uuid.uuid4()}@example.com"
    result = signup(email, TEST_PASSWORD, fake_request)

    assert result["email"] == email
    assert "id" in result

    query("DELETE FROM accounts WHERE id = %s", (result["id"],), nothing_return=True)


def test_signup_rejects_duplicate_email(fake_request):
    email = f"test-signup-dup-{uuid.uuid4()}@example.com"
    result = signup(email, TEST_PASSWORD, fake_request)

    with pytest.raises(ConflictError):
        signup(email, "AnotherPass456!", fake_request)

    query("DELETE FROM accounts WHERE id = %s", (result["id"],), nothing_return=True)


def test_refresh_exchanges_for_a_new_access_token(existing_user, fake_request):
    tokens = login(existing_user, TEST_PASSWORD)
    result = refresh_access_token(tokens["refresh_token"], fake_request)

    assert "access_token" in result
    assert "refresh_token" not in result


def test_refresh_rejects_an_access_token(existing_user, fake_request):
    tokens = login(existing_user, TEST_PASSWORD)

    with pytest.raises(UnauthorizedError):
        refresh_access_token(tokens["access_token"], fake_request)


def test_logout_revokes_the_refresh_token(existing_user, fake_request):
    tokens = login(existing_user, TEST_PASSWORD)

    logout(tokens["refresh_token"], fake_request)

    with pytest.raises(UnauthorizedError):
        refresh_access_token(tokens["refresh_token"], fake_request)


def test_logout_rejects_an_access_token(existing_user, fake_request):
    tokens = login(existing_user, TEST_PASSWORD)

    with pytest.raises(UnauthorizedError):
        logout(tokens["access_token"], fake_request)


def test_request_password_reset_stores_a_token_for_a_known_email(existing_user, fake_request):
    request_password_reset(existing_user, fake_request)

    keys = get_redis().keys("password_reset:*")
    # at least one token now exists — we can't know its exact value here,
    # only that requesting a reset for a real account left something behind
    assert len(keys) >= 1

    for key in keys:
        get_redis().delete(key)


def test_request_password_reset_is_silent_for_an_unknown_email(fake_request):
    # "password_reset:<email>" is the rate-limit counter key, set on every
    # call regardless of whether the email exists — that's expected. A
    # reset *token* key looks like "password_reset:<64 hex chars>", so
    # excluding the rate-limit key itself is what proves no token was
    # actually generated for this unknown address.
    unknown_email = f"no-such-user-{uuid.uuid4()}@example.com"
    rate_limit_key = f"password_reset:{unknown_email}"

    request_password_reset(unknown_email, fake_request)

    token_keys = set(get_redis().keys("password_reset:*")) - {rate_limit_key}
    assert token_keys == set()

    get_redis().delete(rate_limit_key)


def test_request_password_reset_rate_limited_after_three_attempts(fake_request):
    unknown_email = f"rate-limited-{uuid.uuid4()}@example.com"

    for _ in range(3):
        request_password_reset(unknown_email, fake_request)

    with pytest.raises(RateLimitError):
        request_password_reset(unknown_email, fake_request)

    get_redis().delete(f"password_reset:{unknown_email}")


def test_reset_password_changes_the_password(existing_user, fake_request):
    from app.core.security.deps.password_reset import (
        generate_password_reset_token,
        store_password_reset_token,
    )

    sql = "SELECT account_id FROM user_identities WHERE provider = 'email' AND provider_uid = %s"
    user_id = str(query(sql, (existing_user,))[0]["account_id"])

    token = generate_password_reset_token()
    store_password_reset_token(token, user_id)

    new_password = "BrandNewPass456!"
    reset_password(token, new_password)

    with pytest.raises(UnauthorizedError):
        login(existing_user, TEST_PASSWORD)

    result = login(existing_user, new_password)
    assert "access_token" in result


def test_reset_password_rejects_an_invalid_token():
    with pytest.raises(UnauthorizedError):
        reset_password("not-a-real-token", "SomeNewPass456!")


def test_reset_password_rejects_an_already_used_token(existing_user):
    from app.core.security.deps.password_reset import (
        generate_password_reset_token,
        store_password_reset_token,
    )

    sql = "SELECT account_id FROM user_identities WHERE provider = 'email' AND provider_uid = %s"
    user_id = str(query(sql, (existing_user,))[0]["account_id"])

    token = generate_password_reset_token()
    store_password_reset_token(token, user_id)

    reset_password(token, "FirstNewPass456!")

    with pytest.raises(UnauthorizedError):
        reset_password(token, "SecondNewPass456!")
