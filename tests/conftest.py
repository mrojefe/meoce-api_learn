"""Shared test setup — opens the connection pool and Redis client once for
the whole run.

`test_reference_data.py` avoids the pool by using `direct_query` (its own
connection). Any test using `query()` or `check_rate_limit`/Redis directly
needs these open, same as the real app's lifespan does before the first
request.
"""

import pytest

from app.core.db.database import open_pool
from app.core.db.redis import open_redis


@pytest.fixture(scope="session", autouse=True)
def _open_pool():
    open_pool()


@pytest.fixture(scope="session", autouse=True)
def _open_redis():
    open_redis()
