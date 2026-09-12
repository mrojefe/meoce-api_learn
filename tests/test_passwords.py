"""Guards password hashing/verification against the real database.

Integration, not unit: `verify_password_match` reads `user_identities`
directly, so these tests need a reachable database — same reasoning as
`test_reference_data.py`.
"""

import uuid

import pytest

from app.core.db.database import query
from app.core.errors import UnauthorizedError
from app.core.security.deps.passwords import hash_password, verify_password_match

TEST_EMAIL = f"test-passwords-{uuid.uuid4()}@example.com"
TEST_PASSWORD = "TestPass123!"


@pytest.fixture(scope="module")
def test_user():
    """Creates a throwaway account + email identity, cleans it up after."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    query(
        """
        INSERT INTO user_identities (account_id, provider, provider_uid, credential, verified)
        VALUES (%s, 'email', %s, %s, true)
        """,
        (account_id, TEST_EMAIL, hash_password(TEST_PASSWORD)),
        nothing_return=True,
    )

    yield TEST_EMAIL

    query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def test_hash_password_differs_each_call():
    """Same password, two calls, two different hashes — salt is doing its job."""
    h1 = hash_password(TEST_PASSWORD)
    h2 = hash_password(TEST_PASSWORD)
    assert h1 != h2


def test_verify_password_match_accepts_correct_password(test_user):
    """The password used to create the row must verify successfully."""
    assert verify_password_match(TEST_PASSWORD, test_user) is True


def test_verify_password_match_rejects_wrong_password(test_user):
    """A wrong password must raise, never return False silently."""
    with pytest.raises(UnauthorizedError):
        verify_password_match("WrongPassword1!", test_user)


def test_verify_password_match_rejects_unknown_email():
    """No row for this email at all — same error, not a 500."""
    with pytest.raises(UnauthorizedError):
        verify_password_match(TEST_PASSWORD, "nobody-with-this-email@example.com")
