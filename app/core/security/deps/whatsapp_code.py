"""WhatsApp signup/attach codes — random, single-use, stored in Redis.

Same shape as `password_reset.py`/`email_verify.py`, deliberately: this code
proves nothing about *who* holds it, only that whoever texted it to MEOCE's
own WhatsApp number had it. Redis is the only place that knows what this
code was issued for (a brand-new signup, or an attach to an already
authenticated account) — which is why it's looked up (and immediately
deleted) by key, not decoded like a JWT.

A 6-digit code, not a 32-byte hex token like the other two: unlike an email
link, a human has to *type* this into WhatsApp themselves (`MEOCE-123456`),
so it has to stay short enough to type without a copy-paste. That shrinks
the guess space enormously compared to the other tokens, which is exactly
why `check_whatsapp_status` (in `app/services/whatsapp.py`) rate-limits
by the code itself, tightly — the length tradeoff is deliberate, not an
oversight, and the rate limit is what keeps it safe.
"""

import json
import secrets
from datetime import timedelta

from app.core.db.redis import get_redis
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key

WHATSAPP_CODE_TTL_MINUTES = 10


def generate_whatsapp_code() -> str:
    """A random, unguessable 6-digit code, zero-padded.

    `secrets.randbelow`, not `random`: `random` is a deterministic PRNG,
    seeded from predictable state — fine for simulations, never for
    anything a caller must not be able to predict. `secrets` is the
    standard library's own answer to that, same reasoning already applied
    to `generate_password_reset_token`'s `secrets.token_hex`.

    Returns:
        str: Exactly 6 digits, e.g. "004213". Zero-padded so every code is
            the same length — the message a user is asked to send
            (`MEOCE-004213`) must not shrink just because the random draw
            happened to be small.
    """
    return f"{secrets.randbelow(1_000_000):06d}"


def store_whatsapp_code(code: str, payload: dict) -> None:
    """Remembers what a code was issued for, for 10 minutes.

    Args:
        code (str): From `generate_whatsapp_code`.
        payload (dict): `{"issued_at": <unix ts>}` for a signup code, or
            `{"issued_at": <unix ts>, "user_id": "..."}` for an attach
            code — `check_whatsapp_status` branches on whether `user_id`
            is present to tell the two flows apart once the code is
            consumed. Stored as JSON, since Redis itself only holds
            strings/bytes, not a native dict.

    Returns:
        None.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CODE_START, code)
    get_redis().set(key, json.dumps(payload), ex=timedelta(minutes=WHATSAPP_CODE_TTL_MINUTES))


def consume_whatsapp_code(code: str) -> dict | None:
    """Looks up and immediately deletes a code — single use.

    Deleting on read (not just on a confirmed match) matters here exactly
    as it does for `consume_password_reset_token`: once WAHA has actually
    confirmed the matching WhatsApp message came in, this code has done
    its job and must never be usable again, even if `check_whatsapp_status`
    is somehow called a second time with the same value.

    Args:
        code (str): The 6-digit code being resolved.

    Returns:
        dict | None: The stored payload, or None if the code is unknown,
            already used, or expired — those three cases are
            indistinguishable on purpose, same reasoning as
            `consume_password_reset_token`.
    """
    key = valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CODE_START, code)
    r = get_redis()

    raw = r.get(key)
    r.delete(key)

    if raw is None:
        return None

    return json.loads(raw)
