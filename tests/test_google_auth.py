"""Guards Google sign-in against the real database and Redis.

`verify_oauth2_token` is mocked throughout — this test suite never calls
out to real Google, same reasoning as `test_auth.py` never sending a real
email: the network call belongs to Google's own client library, not to
anything this test should be re-proving.
"""

import uuid
from unittest.mock import Mock, patch

import pytest

from app.core.db.database import query
from app.core.db.redis import get_redis
from app.core.errors import RateLimitError, UnauthorizedError
from app.services.auth import login, signup
from app.services.google_auth import google_sign_in

TEST_PASSWORD = "TestPass123!"


@pytest.fixture
def fake_request():
    """A Request stand-in for the rate-limit IP lookup, matching
    `test_auth.py`'s fixture of the same name and reasoning: always
    resolves to the same "unknown" IP, so its rate-limit key is cleaned
    before and after every test that uses it.
    """
    request = Mock()
    request.headers = {}
    request.client = None

    get_redis().delete("google_sign_in:unknown")

    yield request

    get_redis().delete("google_sign_in:unknown")


def _payload(email: str, *, email_verified: bool = True,
             given_name: str = "Jean", family_name: str = "Franck",
             picture: str = "https://example.com/avatar.png",
             sub: str = "google-sub-fixed",
             locale: str | None = "en-US", hd: str | None = None) -> dict:
    """A Google-shaped decoded token payload, the same shape
    `verify_oauth2_token` would hand back on success.

    `sub` defaults to a fixed value rather than a fresh uuid per call so
    that two `_payload()` calls in the same test represent the same
    Google identity by default — callers that want a distinct identity
    (e.g. two different new accounts in the same test) pass their own
    `sub` explicitly.
    """
    return {
        "sub": sub,
        "email": email,
        "email_verified": email_verified,
        "given_name": given_name,
        "family_name": family_name,
        "picture": picture,
        "locale": locale,
        "hd": hd,
    }


def _cleanup(email: str) -> None:
    """Deletes the account owning this email identity, if any.

    NOTE: identity schema is accounts (root) + user_identities (one row
    per login method) -- not a flat users.email column, so cleanup goes
    through user_identities to find the account_id, then deletes the
    account (cascades to user_identities/user_profiles/user_preferences).
    """
    query(
        "DELETE FROM accounts WHERE id = ("
        "SELECT account_id FROM user_identities "
        "WHERE provider = 'email' AND provider_uid = %s)",
        (email,),
        nothing_return=True,
    )


def test_google_sign_in_creates_a_new_account(fake_request):
    email = f"test-google-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, sub=sub, locale="en-US"),
    ):
        result = google_sign_in("fake-id-token", fake_request)

    assert "access_token" in result
    assert "refresh_token" in result

    # NOTE: identity schema is accounts (root) + user_identities (one row
    # per login method) + user_profiles (display) -- not a flat users
    # table. The 'google' identity row carries provider_uid=sub/verified/
    # workspace_domain; the 'email' identity row (added per JF's
    # 2026-09-13 decision) carries the email and has credential NULL for
    # a Google-only account; first_name/last_name/last_login live on
    # user_profiles.
    google_row = dict(query(
        "SELECT provider_uid AS google_sub, workspace_domain AS google_hd "
        "FROM user_identities WHERE account_id = "
        "(SELECT account_id FROM user_identities WHERE provider = 'email' AND provider_uid = %s) "
        "AND provider = 'google'",
        (email,),
    )[0])
    email_row = dict(query(
        "SELECT account_id, credential FROM user_identities "
        "WHERE provider = 'email' AND provider_uid = %s",
        (email,),
    )[0])
    profile_row = dict(query(
        "SELECT first_name, last_name, last_login FROM user_profiles WHERE id = %s",
        (email_row["account_id"],),
    )[0])

    assert email_row["credential"] is None
    assert profile_row["first_name"] == "Jean"
    assert profile_row["last_name"] == "Franck"
    assert google_row["google_sub"] == sub
    assert google_row["google_hd"] is None
    assert profile_row["last_login"] is not None

    prefs = dict(query(
        "SELECT default_language FROM user_preferences WHERE user_id = %s",
        (email_row["account_id"],),
    )[0])
    assert prefs["default_language"] == "en"

    _cleanup(email)


def test_google_sign_in_links_an_existing_password_account(fake_request):
    email = f"test-google-link-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"
    signup(email, TEST_PASSWORD, fake_request)
    get_redis().delete(f"login:{email}")

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, sub=sub),
    ):
        result = google_sign_in("fake-id-token", fake_request)

    assert "access_token" in result

    # A 'google' identity now exists for this account, and the pre-existing
    # 'email' identity's credential was cleared -- see the linking branch
    # of _find_or_link_account.
    account_id = query(
        "SELECT account_id FROM user_identities WHERE provider = 'email' AND provider_uid = %s",
        (email,),
    )[0]["account_id"]
    has_google_identity = query(
        "SELECT EXISTS (SELECT 1 FROM user_identities WHERE account_id = %s AND provider = 'google')",
        (account_id,),
    )[0]["exists"]
    email_credential = query(
        "SELECT credential FROM user_identities WHERE account_id = %s AND provider = 'email'",
        (account_id,),
    )[0]["credential"]

    assert has_google_identity is True
    assert email_credential is None

    with pytest.raises(UnauthorizedError):
        login(email, TEST_PASSWORD)

    _cleanup(email)
    get_redis().delete(f"login:{email}")


def test_google_sign_in_is_idempotent_for_a_returning_user(fake_request):
    email = f"test-google-return-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, sub=sub),
    ):
        first = google_sign_in("fake-id-token", fake_request)
        get_redis().delete("google_sign_in:unknown")
        second = google_sign_in("fake-id-token", fake_request)

    assert "access_token" in first
    assert "access_token" in second

    sql = "SELECT account_id FROM user_identities WHERE provider = 'google' AND provider_uid = %s"
    rows = query(sql, (sub,))
    assert len(rows) == 1

    _cleanup(email)


def test_google_sign_in_resyncs_a_returning_user_from_a_changed_google_profile(fake_request):
    """A returning Google sign-in re-reads Google's *current* claims —
    email, name, picture, locale — not what was recorded at creation, per
    the module's "Google is authoritative for its own fields" policy.
    """
    original_email = f"test-google-changed-{uuid.uuid4()}@example.com"
    new_email = f"test-google-changed-new-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(
            original_email, sub=sub, given_name="Jean", family_name="Franck",
            picture="https://example.com/old.png", locale="en-US",
        ),
    ):
        google_sign_in("fake-id-token", fake_request)

    get_redis().delete("google_sign_in:unknown")

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(
            new_email, sub=sub, given_name="Evan", family_name="Oboumou",
            picture="https://example.com/new.png", locale="fr-FR",
        ),
    ):
        result = google_sign_in("fake-id-token", fake_request)

    assert "access_token" in result

    sql = """
        SELECT ui.account_id, ui.provider_uid AS google_sub,
               p.first_name, p.last_name, p.avatar_url
        FROM user_identities AS ui
        JOIN user_profiles AS p ON p.id = ui.account_id
        WHERE ui.provider = 'google' AND ui.provider_uid = %s
        """
    rows = query(sql, (sub,))
    assert len(rows) == 1  # same account, no duplicate created

    row = dict(rows[0])
    account_id = row["account_id"]

    # email is Google-authoritative too (see _sync_email_identity) -- the
    # account's 'email' identity row should now hold the NEW address, and
    # the OLD address should no longer be claimed by anything.
    current_email = query(
        "SELECT provider_uid FROM user_identities WHERE account_id = %s AND provider = 'email'",
        (account_id,),
    )[0]["provider_uid"]
    old_email_still_claimed = query(
        "SELECT EXISTS (SELECT 1 FROM user_identities WHERE provider = 'email' AND provider_uid = %s)",
        (original_email,),
    )[0]["exists"]

    assert current_email == new_email
    assert old_email_still_claimed is False
    assert row["google_sub"] == sub
    assert row["first_name"] == "Evan"
    assert row["last_name"] == "Oboumou"
    assert row["avatar_url"] == "https://example.com/new.png"

    prefs = dict(query(
        "SELECT default_language FROM user_preferences WHERE user_id = %s",
        (account_id,),
    )[0])
    assert prefs["default_language"] == "fr"

    _cleanup(new_email)


def test_google_sign_in_sets_last_login_on_every_sign_in(fake_request):
    email = f"test-google-lastlogin-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, sub=sub),
    ):
        google_sign_in("fake-id-token", fake_request)

    sql = (
        "SELECT last_login FROM user_profiles WHERE id = "
        "(SELECT account_id FROM user_identities WHERE provider = 'google' AND provider_uid = %s)"
    )
    first_last_login = query(sql, (sub,))[0]["last_login"]
    assert first_last_login is not None

    get_redis().delete("google_sign_in:unknown")

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, sub=sub),
    ):
        google_sign_in("fake-id-token", fake_request)

    second_last_login = query(sql, (sub,))[0]["last_login"]
    assert second_last_login is not None

    _cleanup(email)


def test_google_sign_in_matches_by_google_sub_even_if_email_changed(fake_request):
    """Same as the resync test's core claim, isolated: a later sign-in
    with a *different* email but the *same* `sub` must still resolve to
    the original account, not create a second one — `sub`, not email, is
    the anchor once it's on file.
    """
    first_email = f"test-google-subonly-{uuid.uuid4()}@example.com"
    second_email = f"test-google-subonly-2-{uuid.uuid4()}@example.com"
    sub = f"sub-{uuid.uuid4()}"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(first_email, sub=sub),
    ):
        google_sign_in("fake-id-token", fake_request)

    get_redis().delete("google_sign_in:unknown")

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(second_email, sub=sub),
    ):
        google_sign_in("fake-id-token", fake_request)

    rows = query(
        "SELECT account_id FROM user_identities WHERE provider = 'google' AND provider_uid = %s",
        (sub,),
    )
    assert len(rows) == 1
    account_id = rows[0]["account_id"]

    current_email = query(
        "SELECT provider_uid FROM user_identities WHERE account_id = %s AND provider = 'email'",
        (account_id,),
    )[0]["provider_uid"]
    assert current_email == second_email

    assert query(
        "SELECT EXISTS (SELECT 1 FROM user_identities WHERE provider = 'email' AND provider_uid = %s)",
        (first_email,),
    )[0]["exists"] is False

    _cleanup(second_email)


def test_google_sign_in_rejects_an_invalid_token(fake_request):
    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        side_effect=ValueError("bad token"),
    ), pytest.raises(UnauthorizedError):
        google_sign_in("garbage", fake_request)


def test_google_sign_in_rejects_an_unverified_email(fake_request):
    email = f"test-google-unverified-{uuid.uuid4()}@example.com"

    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        return_value=_payload(email, email_verified=False),
    ), pytest.raises(UnauthorizedError):
        google_sign_in("fake-id-token", fake_request)

    sql = "SELECT EXISTS (SELECT 1 FROM user_identities WHERE provider = 'email' AND provider_uid = %s)"
    assert query(sql, (email,))[0]["exists"] is False


def test_google_sign_in_rate_limited_after_ten_attempts(fake_request):
    with patch(
        "app.services.google_auth.google_id_token.verify_oauth2_token",
        side_effect=ValueError("bad token"),
    ):
        for _ in range(10):
            with pytest.raises(UnauthorizedError):
                google_sign_in("garbage", fake_request)

        with pytest.raises(RateLimitError):
            google_sign_in("garbage", fake_request)
