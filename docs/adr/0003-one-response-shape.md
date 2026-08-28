# ADR-0003: One success shape, one failure shape, nulls included

Date: 2026-08-25
Status: accepted

## Context

A client integrating an API should not need one unwrapping function per
endpoint, nor two ways to read a failure depending on whether the framework or
our code raised it.

## Decision

Success is always `{"data": ..., "meta": {...}}`. Failure is always
`{"error": {"code", "message", "status", "details"}}`. All four of FastAPI's
error paths are overridden so framework errors wear the same shape. Keys are
**always present**, `null` when empty — no `exclude_none`.

## Alternatives considered

**Omit null keys.** Smaller payloads. Rejected: the client then has to test for
presence as well as value, and a key that appears intermittently is a key that
gets forgotten.

**Return bare objects, no envelope.** Simpler for `GET /instruments/{symbol}`.
Rejected: there is then nowhere to put `count`, `as_of` or pagination without
inventing a second shape later.

## Consequences

**Good.** A client writes `unwrap()` once. `"error" in body` decides
success or failure, whatever the endpoint. Adding a `meta` field breaks nobody.

**Bad.** Slightly larger responses, and every response model must be wrapped in
`Envelope[...]`, which is noise in the route signature.

**Trap already met.** Editing the dict *after* `model_dump()` escapes Pydantic
entirely and silently breaks the contract. Build the model, then dump.
