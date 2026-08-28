# ADR-0004: Reference enums live in code, guarded by a test

Date: 2026-08-26
Status: accepted

## Context

`AllowedType`, `AllowedSector`, `AllowedExchange` and `AllowedCurrencyCode`
validate input and are documented in `/openapi.json`. Their values duplicate
rows in reference tables, so they can drift.

The first implementation built them from the database at import, which felt
safer and was not: the API then could not start when the database was
unreachable, `/openapi.json` advertised different values per environment, and
importing a module opened database connections. A `.upper()` applied to the
values also made every response fail validation — the table holds `'bond'`, the
enum had been taught `'BOND'`.

## Decision

The values are **written by hand** in `app/core/enums.py`, on a
`ReferenceStrEnum` base whose `_missing_` hook accepts any case.
`tests/test_reference_data.py` compares them against the tables and fails with
the exact divergence.

## Alternatives considered

**Build from the database at import.** Always fresh. Rejected for the three
costs above.

**No enum, let the foreign key refuse it.** Correct, and the error arrives as a
`ForeignKeyViolation` to translate into a 422 by hand — losing the list of
allowed values in `/docs`.

**Load in the lifespan into a plain dict.** Keeps freshness without import-time
side effects. Rejected because the value would no longer be a *type*, and being
a type is what buys validation and documentation for free.

## Consequences

**Good.** The API starts with no database. `/openapi.json` is identical
everywhere. Unknown values are a 422 listing what is allowed.

**Bad.** Adding a sector in SQL requires a code change. The test makes that
loud (red CI) instead of silent, but it is still two steps.

**Note.** Symbols are deliberately *not* an enum: an open set, and an enum
frozen at startup would reject a symbol this API had just created.
