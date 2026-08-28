# ADR-0001: Talk to PostgreSQL directly with psycopg, not through PostgREST

Date: 2026-08-24
Status: accepted

## Context

MEOCE already runs a self-hosted Supabase. The existing `meoce-api` reaches the
database through `supabase-py`, which speaks to PostgREST, which speaks SQL. The
rewrite had to choose whether to keep that chain.

Two things weighed on the choice. First, PostgREST's filter language (`.eq()`,
`.or_()`, embedded resources) is specific to one product; SQL is not. Second,
two of the three bugs already found in the real API (E-16, E-19) exist
*because* of that filter language — a sector filter applied after `limit`, and
user text concatenated into a filter string. Neither is expressible in SQL with
parameters.

## Decision

We connect straight to PostgreSQL with **psycopg 3** and write SQL by hand.

## Alternatives considered

**Keep `supabase-py`.** Familiar, and it keeps RLS in play. Rejected: the
knowledge does not transfer, and the API would inherit a filter language that
has already produced silent wrong answers.

**An ORM (SQLAlchemy).** Real benefits at scale, and the safe default in the
industry. Rejected *for now*: an ORM is only readable once you know what it
generates. Raw SQL first, a builder later if the queries justify it.

## Consequences

**Good.** SQL transfers to any job and any language. Filtering, ordering and
counting happen in the database, which removes E-16 and E-18 by construction.
Parameters (`%s`) make injection structurally impossible rather than something
to remember.

**Bad, and this one is important.** The API connects as `postgres`, which has
`rolbypassrls = true`. **Row Level Security no longer protects us** — every
ownership check now lives in application code, and forgetting one is a data
leak rather than an empty result set. A future ADR should introduce an
application role without BYPASSRLS.

**Also.** Every query is ours to write and to index. More rope.
