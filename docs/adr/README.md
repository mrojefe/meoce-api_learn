# Architecture Decision Records

One file per decision that was not obvious. Numbered, dated, and **never edited
after the fact** — if a decision is reversed, write a new ADR and mark the old
one superseded. A wrong decision left visible, with its date and its reasoning,
is more useful than a tidy history that hides it.

## Format

Context (what forced a choice) · Decision (one sentence, active voice) ·
Alternatives considered (and why not) · Consequences (**good and bad** — an ADR
with only good consequences is marketing).

## Index

| # | Decision | Date | Status |
|---|---|---|---|
| [0001](0001-postgresql-direct-instead-of-postgrest.md) | Talk to PostgreSQL directly with psycopg, not through PostgREST | 2026-08-24 | accepted |
| [0002](0002-fail-fast-configuration.md) | Configuration is required and validated at startup | 2026-08-24 | accepted |
| [0003](0003-one-response-shape.md) | One success shape, one failure shape, nulls included | 2026-08-25 | accepted |
| [0004](0004-reference-enums-in-code.md) | Reference enums live in code, guarded by a test | 2026-08-26 | accepted |
| [0005](0005-schemas-are-the-only-normaliser.md) | Schemas are the only place that normalises input | 2026-08-26 | accepted |
| [0006](0006-no-default-exchange.md) | No default exchange: ambiguity is a 409, never a guess | 2026-08-26 | accepted |
| [0007](0007-routes-stay-sync.md) | Routes stay `def`, not `async def` | 2026-08-28 | accepted |
| [0008](0008-api-key-for-machines.md) | API key for machines, JWT for people | 2026-08-28 | accepted |
