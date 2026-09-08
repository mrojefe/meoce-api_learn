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
from app.core.errors import ConflictError, RateLimitError
from app.services.whatsapp_auth import (
    check_whatsapp_status,
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

    yield request

    get_redis().delete("whatsapp_code_start:unknown")


def _cleanup(phone: str) -> None:
    query("DELETE FROM users WHERE phone = %s", (phone,), nothing_return=True)


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

    with patch("app.services.whatsapp_auth.httpx.get", side_effect=_mock_waha(messages=[])):
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
        "app.services.whatsapp_auth.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status["status"] == "confirmed"
    assert "access_token" in status
    assert "refresh_token" in status

    row = dict(query(
        "SELECT phone, phone_verified, auth_provider FROM users WHERE phone = %s",
        (sender_chat_id,),
    )[0])
    assert row["phone_verified"] is True
    assert row["auth_provider"] == "whatsapp"

    _cleanup(sender_chat_id)


def test_status_logs_into_an_existing_phone_without_duplicating_it(fake_request):
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"
    existing = query(
        "INSERT INTO users (phone, phone_verified, auth_provider) "
        "VALUES (%s, true, 'whatsapp') RETURNING id",
        (sender_chat_id,),
    )[0]
    existing_id = str(existing["id"])

    result = start_whatsapp_signup(fake_request)
    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp_auth.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status["status"] == "confirmed"

    rows = query("SELECT id FROM users WHERE phone = %s", (sender_chat_id,))
    assert len(rows) == 1
    assert str(rows[0]["id"]) == existing_id

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
        "app.services.whatsapp_auth.httpx.get",
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
        "app.services.whatsapp_auth.httpx.get",
        side_effect=_mock_waha(messages=[outbound_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "pending"}


def test_attach_succeeds_for_an_authenticated_user(fake_request):
    new_user = query(
        "INSERT INTO users (email, password_hash) VALUES (%s, 'x') RETURNING id",
        (f"test-attach-{uuid.uuid4()}@example.com",),
    )[0]
    user_id = str(new_user["id"])

    result = start_whatsapp_attach(user_id, fake_request)
    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"

    matching_message = {
        "from": sender_chat_id,
        "fromMe": False,
        "timestamp": time.time() + 1,
        "body": f"MEOCE-{result['code']}",
    }

    with patch(
        "app.services.whatsapp_auth.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ):
        status = check_whatsapp_status(result["code"])

    assert status == {"status": "confirmed"}
    assert "access_token" not in status

    row = dict(query(
        "SELECT phone, phone_verified FROM users WHERE id = %s", (user_id,),
    )[0])
    assert row["phone"] == sender_chat_id
    assert row["phone_verified"] is True

    query("DELETE FROM users WHERE id = %s", (user_id,), nothing_return=True)


def test_attach_rejects_a_phone_already_claimed_by_another_account(fake_request):
    other_user = query(
        "INSERT INTO users (email, password_hash) VALUES (%s, 'x') RETURNING id",
        (f"test-attach-other-{uuid.uuid4()}@example.com",),
    )[0]
    other_id = str(other_user["id"])

    sender_chat_id = f"test-{uuid.uuid4().hex[:10]}@c.us"
    query(
        "INSERT INTO users (phone, phone_verified, auth_provider) "
        "VALUES (%s, true, 'whatsapp')",
        (sender_chat_id,),
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
        "app.services.whatsapp_auth.httpx.get",
        side_effect=_mock_waha(messages=[matching_message]),
    ), pytest.raises(ConflictError):
        check_whatsapp_status(result["code"])

    query("DELETE FROM users WHERE id = %s", (other_id,), nothing_return=True)
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
