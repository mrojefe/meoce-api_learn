"""Redis access — one client for the whole application.

Opened once at startup and left open until the process exits (see the
lifespan in main.py, same as `database.py`'s pool). Short-lived, disposable
data only — email-verify tokens, rate-limit counters — never a system of
record; that stays in Postgres.
"""

import redis

from app.core.config import get_settings

_client: redis.Redis | None = None


def open_redis() -> None:
    """Creates the Redis client. Call once, at application startup.

    `global` is required because the assignment must update the module-level
    `_client`, not create a local copy.

    Returns:
        None

    Examples:
        >>> open_redis()          # in the lifespan, before the first request
    """
    global _client
    s = get_settings()

    _client = redis.Redis(
        host=s.redis_host,
        port=s.redis_port,
        username=s.redis_username,
        password=s.redis_password.get_secret_value(),
        decode_responses=True,
    )


def close_redis() -> None:
    """Closes the client and forgets it. Call once, at application shutdown.

    Setting `_client` back to None means a later `get_redis()` raises a clear
    error instead of handing out a closed client.

    Returns:
        None
    """
    global _client
    if _client is not None:
        _client.close()
        _client = None


def get_redis() -> redis.Redis:
    """Returns the open client.

    Every other module asks for the client through this function rather than
    importing `_client` directly, so how it is stored can change in one place.

    Returns:
        redis.Redis: The client created by `open_redis()`.

    Raises:
        RuntimeError: If the client was never opened — which means the
            application did not start correctly.
    """
    if _client is None:
        raise RuntimeError("redis client not opened — did the app start correctly?")
    return _client
