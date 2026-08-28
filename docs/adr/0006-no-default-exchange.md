# ADR-0006: No default exchange — ambiguity is a 409, never a guess

Date: 2026-08-26
Status: accepted

## Context

The unique constraint on `instruments` is `(exchange_id, symbol)`, not `symbol`
alone. The same ticker may therefore legitimately exist on the BRVM and on the
NGX — and MEOCE's roadmap is BRVM today, Nigeria and Morocco next.

`get_by_symbol` queried `WHERE symbol = %s` and returned `rows[0]`: whichever
row Postgres happened to return first. For market data, the wrong exchange means
the wrong price. Filed as E-20.

## Decision

`exchange` is **optional**, with **no default**. One match is returned. Several
matches with no exchange given returns **409**, naming the exchanges so the
caller can retry precisely.

## Alternatives considered

**Default to BRVM.** Convenient, and every existing caller keeps working.
Rejected: it does not remove the silence, it relocates it — a caller who meant
NGX still receives BRVM prices, with no error.

**Make `exchange` required.** Never ambiguous. Rejected: it burdens every
caller for a problem that only exists for symbols listed twice.

## Consequences

**Good.** The API cannot return a confidently wrong price. The 409 message
names the exchanges, so it is actionable rather than merely refusing.

**Bad.** A caller can be surprised by a 409 on a request that worked yesterday,
the day a symbol is listed on a second exchange. That is the intended trade:
a visible break rather than a silent wrong number.
