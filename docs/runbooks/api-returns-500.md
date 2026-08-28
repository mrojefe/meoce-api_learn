# Requests return 500, or bare text

**First: look at the shape of the answer.** It tells you which half of the
system failed, before you read anything else.

| What you see | What it means |
|---|---|
| `{"error":{"code":"internal_error",...}}` — JSON, our contract | the catch-all handler **ran**. The app is alive; one request hit a bug |
| `Internal Server Error` — bare text | our handlers **never ran**. The application itself failed |
| `Invalid HTTP request received` — bare text, 400 | uvicorn rejected malformed HTTP before FastAPI existed. Usually a bad `curl` — a space before a header's colon, or a newline inside a header value |

## JSON 500 — a bug in one route

The body says nothing on purpose (a stack trace tells an attacker the file
layout, the library versions and often the SQL). The traceback is in the
**server's terminal**, logged by `unhandled_error_handler`.

Reproduce it outside HTTP, where the traceback is complete:

```bash
PYTHONPATH=$PWD uv run python -c "
from app.core.database import open_pool
from app.services.instruments import list_instruments
open_pool()
print(list_instruments(limit=2))
"
```

Note `open_pool()` — the pool is normally opened by the lifespan, which only
runs under uvicorn. Without it: *"pool not opened — did the app start
correctly?"*, which is correct behaviour, not a bug.

### ⚠️ A 500 does not mean nothing happened

A write can commit and the *response* still fail. Measured 2026-08-26:
`POST /instruments` returned 500 four times and created four rows — the insert
succeeded, then the response model rejected the row because `RETURNING` was
missing a column. **Check the database before retrying**, and before telling
anyone the request failed.

## Bare text 500 — the application is broken

Handlers never ran. Look at startup: see `api-will-not-start.md`.

## A 500 that only appears sometimes

Suspect the pool. `max_size=5`; a connection leaked per request exhausts it, and
request six waits forever. Ask the database who is connected and what they are
waiting on:

```sql
SELECT pid, state, wait_event_type, left(query, 60)
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid();
```

`idle in transaction` means someone opened a transaction and never closed it —
that connection is holding locks.
