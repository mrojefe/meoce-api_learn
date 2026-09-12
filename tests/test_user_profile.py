"""Guards the profile read/update services against the real database.

Covers only §1 of the profile work so far: `country`/`profile_completed`
write support via `update_identity_fields`, and that `get_profile` reads
them back. `update_profile`'s `user_profiles`-table behavior already has no direct
coverage elsewhere either, so this file sticks to what's new here.
"""

import uuid

import pytest

from app.core.db.database import query
from app.services.user_profile import get_profile, update_identity_fields, update_profile

TEST_PASSWORD_HASH = "not-a-real-hash"


@pytest.fixture
def existing_user():
    """A throwaway account: accounts + user_identities ('email') +
    user_profiles rows, all inserted directly -- no mirror trigger creates
    user_profiles under this schema, unlike the old flat users table.
    """
    email = f"test-profile-{uuid.uuid4()}@example.com"
    user_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, credential, verified) "
        "VALUES (%s, 'email', %s, %s, true)",
        (user_id, email, TEST_PASSWORD_HASH),
        nothing_return=True,
    )
    query(
        "INSERT INTO user_profiles (id) VALUES (%s)",
        (user_id,),
        nothing_return=True,
    )

    yield user_id

    query("DELETE FROM accounts WHERE id = %s", (user_id,), nothing_return=True)


def test_update_identity_fields_writes_country_only(existing_user):
    update_identity_fields(existing_user, {"country": "CI"})

    profile = get_profile(existing_user)
    assert profile["country"] == "CI"
    assert profile["profile_completed"] is False


def test_update_identity_fields_writes_profile_completed_only(existing_user):
    update_identity_fields(existing_user, {"profile_completed": True})

    profile = get_profile(existing_user)
    assert profile["profile_completed"] is True
    assert profile["country"] is None


def test_update_identity_fields_writes_both_together(existing_user):
    update_identity_fields(existing_user, {"country": "CI", "profile_completed": True})

    profile = get_profile(existing_user)
    assert profile["country"] == "CI"
    assert profile["profile_completed"] is True


def test_update_identity_fields_empty_dict_is_a_noop(existing_user):
    update_profile(existing_user, {"display_name": "before"})

    update_identity_fields(existing_user, {})

    profile = get_profile(existing_user)
    assert profile["country"] is None
    assert profile["profile_completed"] is False
    assert profile["display_name"] == "before"


def test_update_identity_fields_ignores_unwhitelisted_keys(existing_user):
    # Even if a caller somehow passed a disallowed key (schema layer would
    # never allow this today), it must be silently dropped, never written.
    update_identity_fields(existing_user, {"country": "CI", "email": "hacked@example.com"})

    profile = get_profile(existing_user)
    assert profile["country"] == "CI"
    assert profile["email"] != "hacked@example.com"
