"""Guards check_rate_limit against the real Redis instance."""

import pytest

from app.core.db.redis import get_redis, open_redis
from app.core.errors import RateLimitError
from app.core.security.deps.rate_limit import check_rate_limit

TEST_KEY = "login:test-rate-limit@example.com"


@pytest.fixture(autouse=True)
def _clean_key():
    """Every test starts and ends with a clean counter."""
    open_redis()
    get_redis().delete(TEST_KEY)
    yield
    get_redis().delete(TEST_KEY)


def test_allows_up_to_the_limit():
    """max_attempts calls in a row must all succeed."""
    for _ in range(3):
        check_rate_limit(TEST_KEY, max_attempts=3, window_seconds=60)


def test_blocks_past_the_limit():
    """The call right after the limit must raise."""
    for _ in range(3):
        check_rate_limit(TEST_KEY, max_attempts=3, window_seconds=60)

    with pytest.raises(RateLimitError):
        check_rate_limit(TEST_KEY, max_attempts=3, window_seconds=60)


def test_sets_an_expiry_on_first_hit():
    """The window must actually reset itself — no expiry means a
    permanent lockout after the first burst.
    """
    check_rate_limit(TEST_KEY, max_attempts=3, window_seconds=60)

    ttl = get_redis().ttl(TEST_KEY)
    assert 0 < ttl <= 60


def test_rejects_an_unknown_key_prefix():
    """A key that doesn't start with a known action name must be
    refused — catches a typo before it silently creates a stray counter.
    """
    with pytest.raises(ValueError):
        check_rate_limit("not-a-real-prefix:whatever", max_attempts=3, window_seconds=60)
