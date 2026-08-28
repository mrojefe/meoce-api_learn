# ADR-0007: Routes stay `def`, not `async def`

Date: 2026-08-28
Status: accepted

## Context

FastAPI accepts both. The real `meoce-api` writes `async def` on routes that
then call blocking Supabase clients — which is the worst of the two: the
function occupies the event loop and never yields, where a plain `def` would
have been handed to a thread.

psycopg is used in its blocking mode here.

## Decision

Routes and services stay **`def`**. FastAPI runs them in its threadpool, where
blocking is harmless.

## Alternatives considered

**`async def` everywhere with `AsyncConnectionPool`.** Coherent, and correct if
adopted wholesale — every service and route becomes `async`, every `query()`
becomes `await query()`. Rejected: the gain is unmeasurable for CRUD reads, and
the change touches every file.

**`async def` routes over blocking calls.** What the real API does. Rejected: it
is strictly worse than `def`.

## Consequences

**Good.** No event loop to starve. Blocking libraries — psycopg, `requests`,
file reads — are usable without care.

**Bad.** Concurrency is bounded by the threadpool, and a thread costs ~8 MB
against a coroutine's few KB. Irrelevant at CRUD scale.

**When to revisit.** Streaming live prices to thousands of open connections.
Then threads genuinely cannot be used, and this ADR gets superseded.
