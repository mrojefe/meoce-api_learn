# ADR-0009: Authentication moves into the API

Date: 2026-09-02
Status: **accepted, not yet implemented**

## Context

Today MEOCE mints its own tokens in the **frontend repo**:

```
src/lib/auth.ts                        generateJWT(userId)  — signs with JWT_SECRET
src/app/api/auth/verify-otp/route.ts   calls it after the OTP is verified
meoce-api/app/core/security/deps.py    only ever VERIFIES
```

The API can check a token but cannot issue one. `JWT_SECRET` therefore has to exist in two
places — Vercel and the API host — and stay identical.

This is a normal pattern **when Next.js is the whole backend** (it is what NextAuth /
Auth.js do). MEOCE is not that case: there is a separate API. The layout is the result of
the website being built first and the API arriving later, not of a decision.

## Decision

Authentication becomes the API's job. The API owns login, issues access and refresh
tokens, and is the only holder of `JWT_SECRET`. The frontend calls it like any other
client:

```
POST /api/v1/auth/request-otp
POST /api/v1/auth/verify-otp     -> access token + refresh cookie
POST /api/v1/auth/refresh
POST /api/v1/auth/logout         -> adds the jti to the denylist
```

## Alternatives considered

**Leave it as it is.** It works, and nothing is broken. Rejected as the default rather than
as a plan: the cost only appears later, and later is when it is expensive to change.

**Move to a hosted provider (Auth0) instead.** Would also solve it. Rejected for the
reasons recorded against that question: it prices per monthly active user, users already
live in our database, and it would replace only the login — ownership checks and
entitlements stay ours either way.

## Consequences

**Good.** One holder of the secret instead of two. Anything that is not a browser — a
mobile app, a partner integration, a CLI — can authenticate. Revocation, account status
and rate limiting on login all land in one place instead of two. The frontend stops being
security-critical code.

**Bad.** A real migration: the OTP flow, email sending, refresh rotation and the cookie all
move. Both paths must work at once during the switch, and every existing session must keep
working — the tokens are compatible, since it is the same secret and the same claims.

**Not urgent.** It becomes urgent the day something that is not the website needs to log
in. Deliberately after the current security work, and after the frontend course.
