"""Security machinery: who is calling, and may they.

Currently one module:

* `deps.py` — the dependencies routes attach. `require_api_key` for machines
  (Airflow), `get_current_user_id` for people (a JWT minted by the frontend).

Three things this package does NOT yet do, each waiting to be built rather than
copied:

* **revocation** — a logged-out token stays valid until it expires, because
  nothing checks a denylist. Needs Redis.
* **account status** — a banned account keeps working until its token expires.
  Needs a lookup, and a cache so it does not cost a query per request.
* **rate limiting** — one caller can ask as often as it likes.

They were present as copies from the production API and removed on 2026-09-02:
they never ran, they referenced a Supabase client this app does not have, and
code nobody here can explain does not belong in this repo.
"""
