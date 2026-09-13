"""Guards the WhatsApp signup/attach flow against the real database, Redis,
and WAHA.

Every WAHA HTTP call (`check-exists`, `messages`) is mocked throughout —
this suite never calls real WAHA, same reasoning as `test_google_auth.py`
never calling real Google: rate limits, real WhatsApp messages, and
non-deterministic timing have no place in a unit test.
"""

import time
import uuid
from unittest.mock import Mock, patch

import pytest

from app.core.db.database import query
from app.core.db.redis import get_redis
from app.core.errors import ApiError, ConflictError, RateLimitError
from app.services.whatsapp import (
    check_whatsapp_exists,
    check_whatsapp_status,
    send_message,
    start_whatsapp_attach,
    start_whatsapp_signup,
)


@pytest.fixture
def fake_request():
    """A Request stand-in for the rate-limit IP lookup, same shape and
    reasoning as `test_google_auth.py`'s fixture of the same name.
    """
    request = Mock()
    request.headers = {}
    request.client = None

    get_redis().delete("whatsapp_code_start:unknown")
    get_redis().delete("whatsapp_check:unknown")

    yield request

    get_redis().delete("whatsapp_code_start:unknown")
    get_redis().delete("whatsapp_check:unknown")


def _cleanup(phone: str) -> None:
    """Deletes the account owning this whatsapp identity, if any.

    NOTE: identity schema is accounts (root) + user_identities (one row
    per login method) -- not a flat users.phone column.
    """
    query(
        "DELETE FROM accounts WHERE id = ("
        "SELECT account_id FROM user_identities "
        "WHERE provider = 'whatsapp' AND provider_uid = %s)",
        (phone,),
        nothing_return=True,
    )


def _mock_waha(*, chat_id: str = "99912345@lid", messages: list[dict] | None = None):
    """Builds the two mocked httpx responses `_waha_check_exists` and
    `_waha_fetch_recent_messages` expect: a `check-exists` response (just
    `chatId`) and a `messages` response (a list of message dicts).

    Returns:
        Mock: to be used as the `side_effect` of a single `httpx.get` patch
            — `check-exists` is called first, `messages` second, matching
            `_find_matching_phone`'s own call order.
    """
    check_exists_response = Mock()
    check_exists_response.json.return_value = {"numberExists": True, "chatId": chat_id}
    check_exists_response.raise_for_status.return_value = None

    messages_response = Mock()
    messages_response.json.return_value = messages or []
    messages_response.raise_for_status.return_value = None

    return [check_exists_response, messages_response]


def test_start_whatsapp_signup_returns_a_six_digit_code(fake_request):
    result = start_whatsapp_signup(fake_request)

    assert len(result["code"]) == 6
    assert result["code"].isdigit()
    assert result["whatsapp_number"]
    assert result["expires_in_seconds"] > 0


def test_status_is_pending_before_any_message(fake_request):
    result = start_whatsapp_signup(fake_request)

    with patch("app.services.whatsapp.httpx.get", side_effect=_mock_waha(messages=[])):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "pending"}


def test_status_is_pending_for_an_unknown_code():
    assert check_whatsapp_status("000000") == {"status": "pending"}


def test_status_confirms_a_new_signup_on_a_matching_message(fake_request):
    result = start_whatsapp_signup(fake_request)
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"

    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status["status"] == "confirmed"
    assert "access_token" in status
    assert "refresh_token" in status

    row = dict(query(
        "SELECT verified FROM user_identities WHERE provider = 'whatsapp' AND provider_uid = %s",
        (sender_chat_id,),
    )[0])
    assert row["verified"] is True

    _cleanup(sender_chat_id)


def test_status_logs_into_an_existing_phone_without_duplicating_it(fake_request):
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"
    existing_id = str(query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"])
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, verified, verified_at) "
        "VALUES (%s, 'whatsapp', %s, true, now())",
        (existing_id, sender_chat_id),
        nothing_return=True,
    )

    result = start_whatsapp_signup(fake_request)
    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status["status"] == "confirmed"

    rows = query(
        "SELECT account_id FROM user_identities WHERE provider = 'whatsapp' AND provider_uid = %s",
        (sender_chat_id,),
    )
    assert len(rows) == 1
    assert str(rows[0]["account_id"]) == existing_id

    _cleanup(sender_chat_id)


def test_status_ignores_a_message_sent_before_the_code_was_issued(fake_request):
    result = start_whatsapp_signup(fake_request)
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"

    stale_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() - 3600,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[stale_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "pending"}


def test_status_ignores_outbound_messages(fake_request):
    result = start_whatsapp_signup(fake_request)

    outbound_message = {
        "from": "99854315425806@lid",
        "fromMe": True,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[outbound_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "pending"}


def test_attach_succeeds_for_an_authenticated_user(fake_request):
    user_id = str(query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"])
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, credential) "
        "VALUES (%s, 'email', %s, 'x')",
        (user_id, f"test-attach-{uuid.uuid4()}@example.com"),
        nothing_return=True,
    )

    result = start_whatsapp_attach(user_id, fake_request)
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"

    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "confirmed"}
    assert "access_token" not in status

    row = dict(query(
        "SELECT provider_uid, verified FROM user_identities "
        "WHERE account_id = %s AND provider = 'whatsapp'",
        (user_id,),
    )[0])
    assert row["provider_uid"] == sender_chat_id
    assert row["verified"] is True

    query("DELETE FROM accounts WHERE id = %s", (user_id,), nothing_return=True)


def test_attach_rejects_a_phone_already_claimed_by_another_account(fake_request):
    other_id = str(query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"])
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, credential) "
        "VALUES (%s, 'email', %s, 'x')",
        (other_id, f"test-attach-other-{uuid.uuid4()}@example.com"),
        nothing_return=True,
    )

    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"
    other_account_with_phone = str(query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"])
    query(
        "INSERT INTO user_identities (account_id, provider, provider_uid, verified, verified_at) "
        "VALUES (%s, 'whatsapp', %s, true, now())",
        (other_account_with_phone, sender_chat_id),
        nothing_return=True,
    )

    result = start_whatsapp_attach(other_id, fake_request)
    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ), pytest.raises(ConflictError):
        check_whatsapp_status(result["code"])

    query("DELETE FROM accounts WHERE id = %s", (other_id,), nothing_return=True)
    _cleanup(sender_chat_id)


def test_start_whatsapp_signup_is_rate_limited(fake_request):
    for _ in range(5):
        start_whatsapp_signup(fake_request)

    with pytest.raises(RateLimitError):
        start_whatsapp_signup(fake_request)


def test_status_is_rate_limited_per_code(fake_request):
    code = "555555"
    get_redis().delete(f"whatsapp_code_guess:{code}")

    for _ in range(20):
        check_whatsapp_status(code)

    with pytest.raises(RateLimitError):
        check_whatsapp_status(code)

    get_redis().delete(f"whatsapp_code_guess:{code}")


def test_check_whatsapp_exists_true(fake_request):
    mock_response = Mock()
    mock_response.json.return_value = {"numberExists": True, "chatId": "2250767386180@c.us"}
    mock_response.raise_for_status.return_value = None

    with patch("app.services.whatsapp.httpx.get", return_value=mock_response):
        assert check_whatsapp_exists("2250767386180", fake_request) is True


def test_check_whatsapp_exists_false(fake_request):
    mock_response = Mock()
    mock_response.json.return_value = {"numberExists": False, "chatId": None}
    mock_response.raise_for_status.return_value = None

    with patch("app.services.whatsapp.httpx.get", return_value=mock_response):
        assert check_whatsapp_exists("0000000000", fake_request) is False


def test_check_whatsapp_exists_is_rate_limited(fake_request):
    mock_response = Mock()
    mock_response.json.return_value = {"numberExists": True, "chatId": "x@c.us"}
    mock_response.raise_for_status.return_value = None

    with patch("app.services.whatsapp.httpx.get", return_value=mock_response):
        for _ in range(20):
            check_whatsapp_exists("2250767386180", fake_request)

        with pytest.raises(RateLimitError):
            check_whatsapp_exists("2250767386180", fake_request)


def test_send_message_refuses_without_a_verified_whatsapp_identity():
    """No user_identities row at all -- the structural gate, not a trust-the-
    caller check, refuses before any WAHA call is even attempted."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]

    try:
        with pytest.raises(ApiError):
            send_message(account_id, "hello")
    finally:
        query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def test_send_message_refuses_an_unverified_whatsapp_identity():
    """A whatsapp identity row exists but verified=false (never confirmed by
    an inbound message) -- still refused, same as having none at all."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    sql = """
        INSERT INTO user_identities (account_id, provider, provider_uid, verified)
        VALUES (%s, 'whatsapp', '2250700000000', false)
        """
    query(sql, (account_id,), nothing_return=True)

    try:
        with pytest.raises(ApiError):
            send_message(account_id, "hello")
    finally:
        query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)


def test_send_message_sends_to_a_verified_contact():
    """A verified=true whatsapp identity -- the account already texted
    MEOCE first (that's the only way verified ever becomes true) -- is
    allowed through to WAHA."""
    account_id = query("INSERT INTO accounts DEFAULT VALUES RETURNING id")[0]["id"]
    sql = """
        INSERT INTO user_identities (account_id, provider, provider_uid, verified)
        VALUES (%s, 'whatsapp', '2250700000001', true)
        """
    query(sql, (account_id,), nothing_return=True)

    check_response = Mock()
    check_response.json.return_value = {"chatId": "2250700000001@c.us"}
    check_response.raise_for_status.return_value = None

    send_response = Mock()
    send_response.json.return_value = {"id": "waha-msg-1"}
    send_response.raise_for_status.return_value = None

    try:
        with patch("app.services.whatsapp.httpx.get", return_value=check_response), \
             patch("app.services.whatsapp.httpx.post", return_value=send_response) as mock_post:
            message_id = send_message(account_id, "hello")

        assert message_id == "waha-msg-1"
        mock_post.assert_called_once()
        assert mock_post.call_args.kwargs["json"]["chatId"] == "2250700000001@c.us"
    finally:
        query("DELETE FROM accounts WHERE id = %s", (account_id,), nothing_return=True)
