"""Guards token creation/verification. No database needed — pure token
mechanics, unlike test_passwords.py.
"""

from unittest.mock import Mock

import pytest

from app.core.errors import UnauthorizedError
from app.core.security.deps.jwt import (
    _decode,
    create_access_token,
    create_refresh_token,
)
from app.schemas.jwt import TokenAudience

USER_ID = "c028c759-5fee-402b-a09f-ef39f3c22f31"


@pytest.fixture
def fake_request():
    """A Request stand-in — `_decode` only reads it for logging on failure."""
    request = Mock()
    request.headers = {}
    request.client = None
    return request


def test_access_token_round_trips(fake_request):
    """Create an access token, decode it back, get the same user id."""
    token = create_access_token(USER_ID)
    assert _decode(token, TokenAudience.ACCESS, fake_request).userId == USER_ID


def test_refresh_token_round_trips(fake_request):
    """Same for refresh, checked against its own audience."""
    token = create_refresh_token(USER_ID)
    assert _decode(token, TokenAudience.REFRESH, fake_request).userId == USER_ID


def test_refresh_token_rejected_as_access_token(fake_request):
    """A refresh token must never work where an access token belongs —
    the whole point of stamping each token with its audience.
    """
    refresh_token = create_refresh_token(USER_ID)
    with pytest.raises(UnauthorizedError):
        _decode(refresh_token, TokenAudience.ACCESS, fake_request)


def test_access_token_rejected_as_refresh_token(fake_request):
    """And the reverse: an access token must not work as a refresh token."""
    access_token = create_access_token(USER_ID)
    with pytest.raises(UnauthorizedError):
        _decode(access_token, TokenAudience.REFRESH, fake_request)


def test_garbage_token_rejected(fake_request):
    """A string that isn't a JWT at all must raise, not crash differently."""
    with pytest.raises(UnauthorizedError):
        _decode("not-a-real-token", TokenAudience.ACCESS, fake_request)
