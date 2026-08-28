# ADR-0005: Schemas are the only place that normalises input

Date: 2026-08-26
Status: accepted

## Context

`symbol` was being stripped and uppercased twice: once by `Symbol`'s validator
in the schema, once again by `.upper().strip()` in the service. `exchange` was
normalised only in the schema. Same file, two different rules.

## Decision

**Schemas normalise; services trust.** `Symbol` strips and uppercases, the
reference enums resolve case to the database's exact spelling, and service
functions receive canonical values and repeat none of that work.

## Alternatives considered

**Normalise in the service too (belt and braces).** Defensible: a service may
be called from a script or a test where no schema ran. Rejected: two copies of
a rule is two places to update, and the second one is the one that drifts.

## Consequences

**Good.** One place per rule. Verified rather than assumed: `'ngx'` reaches the
database as `'NGX'`, `'Londre'` never reaches it at all.

**Bad.** A service called directly — from a notebook, a script, a future
Airflow task — receives whatever it is given. If services ever become a public
entry point, this ADR needs revisiting.
