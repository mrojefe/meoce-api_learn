# ADR-0002: Configuration is required and validated at startup

Date: 2026-08-24
Status: accepted

## Context

E-15, found in the real API: `env` defaulted to `"dev"`. A production deploy
missing `MEOCE_ENV` therefore believed it was in development and served `/docs`
publicly. Nothing failed; the default was simply wrong, quietly.

## Decision

Settings are declared in `app/core/config.py` with **no defaults for anything
environment-specific**, and validated by pydantic-settings at import. A missing
variable stops the application from starting. Secrets are `SecretStr`.

## Alternatives considered

**Sensible defaults.** Convenient locally. Rejected: a default is a guess about
production made by someone who is not there.

**Check at first use.** Rejected: the failure then happens on a request, hours
later, to a user rather than to the deploy.

## Consequences

**Good.** A misconfigured deploy fails at boot, loudly, in front of whoever
deployed it. `SecretStr` keeps passwords out of logs and `repr()`.

**Bad.** Every new environment must set every variable — no `git clone && run`.
`.env.example` exists to make that survivable.

**Known limit.** `SecretStr` does not protect a `ValidationError` raised by
`Settings()` itself, which prints the offending value. Measured, not assumed.
