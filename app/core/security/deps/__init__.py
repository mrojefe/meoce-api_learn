"""Dependencies — the checks that run *before* a route, not inside it.

A dependency is a function FastAPI calls first, whose result it passes to the
route. Two things make that worth doing for security:

* **It cannot be forgotten.** Written inside the route, an auth check is copied
  into every protected endpoint, and the fifteenth copy is the one that drifts.
  Written here, it is declared once and applied by the decorator.
* **A raise stops the route.** If this file raises, the endpoint body never
  runs — the route is unreachable without credentials, by construction rather
  than by discipline.

Split three ways by concern:

* `api_key.py` — machine-to-machine auth (Airflow's shared secret).
* `jwt.py` — token mechanics: is this JWT genuine.
* `user.py` — identity and entitlements: who is this, what does their plan allow.

Everything is re-exported here so `from app.core.security.deps import X`
keeps working unchanged.
"""

from app.core.security.deps.api_key import require_api_key
from app.core.security.deps.user import (
    get_current_entitlements,
    get_current_user_id,
    require_feature,
)

__all__ = [
    "get_current_entitlements",
    "get_current_user_id",
    "require_api_key",
    "require_feature",
]
