# ADR-0008: API key for machines, JWT for people

Date: 2026-08-28
Status: accepted

## Context

`POST /instruments` was open to the internet. Instruments are written by
Airflow — a machine, with no human to log in, nothing to type, and no session
to expire.

## Decision

Machine-to-machine calls authenticate with a **shared API key** in the
`X-API-KEY` header, checked by a route dependency. Human callers will
authenticate with a **JWT** (module 10). A route may require either or both.

The key is compared with `hmac.compare_digest`, and declared through
`APIKeyHeader` rather than a plain `Header`.

## Alternatives considered

**A service-account JWT for Airflow.** One mechanism instead of two. Rejected:
a JWT expires and must be refreshed, which means giving a DAG a login flow to
solve a problem it does not have.

**Compare with `==`.** Rejected: string comparison stops at the first differing
character, so rejection time leaks how many leading characters were right. A
32-character secret falls in ~2,000 tries instead of 64³².

**Plain `Header(...)`.** Identical at runtime. Rejected: OpenAPI then describes
the credential as an optional parameter (`required: false`), so a generated
client omits it, and `/docs` shows no padlock and no Authorize button.

## Consequences

**Good.** The endpoint is unreachable without the key by construction — a raise
in a dependency stops the route. `/docs` documents it as a credential.

**Bad.** One shared secret: rotating it means coordinating every system that
holds it, and the logs cannot say *which* caller it was. Per-system keys in a
table would fix both, and are not worth it for one caller.

**Open.** Failed attempts are not logged. 10,000 rejected keys currently look
exactly like an idle server (`QUESTIONS_OPEN.md` Q-05).
