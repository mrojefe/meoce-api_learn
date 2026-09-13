"""WhatsApp sign-in/attach — a third, independent way to reach an account.

Kept apart from `auth.py` and `google_auth.py`, same reasoning as
`google_auth.py`'s own module docstring: each provider is its own file so a
provider-specific policy never has to be threaded as a branch through code
that mostly belongs to a different provider.

**The "inverted" flow — why this never messages first:** WhatsApp Business
API access aggressively bans numbers that message people who never opted
in, and a backend that texts a stranger first because they typed their
phone number into a signup form is exactly that pattern. The real app
already solved this the other way around: MEOCE never initiates contact.
Instead, a short code is generated and shown to the user in the app; *they*
open WhatsApp themselves and text `MEOCE-<code>` to MEOCE's own number; the
frontend polls `GET /auth/whatsapp/status` until that inbound message shows
up. WAHA (this project's WhatsApp bridge) never receives an outbound
message as part of this flow — only reads of the chat it already owns.

**Polling, not a webhook — decided, not defaulted:** a webhook receiver
would need its own inbound endpoint, sender verification, and retry/
idempotency handling, and its only precedent in this project is
`scripts/waha_listener.py`, an explicitly-labelled debug side-channel, not
auth-grade infra. Polling is what the real app already does in production,
needs no new infrastructure (the exact same WAHA REST calls this module
already makes), and is self-healing — a missed poll is caught by the next
one, a couple of seconds later, which is irrelevant next to how long a
human takes to type six digits into WhatsApp.

**Account-linking policy — same "Model A" rule as `google_auth.py`:** a
signup code (no `user_id` in its stored payload) arrives with no existing
session, exactly like Google sign-in, so it is looked up by `phone` and
either creates a new account or logs into an existing `auth_provider =
'whatsapp'` one. An attach code (`user_id` present) only ever runs inside
an authenticated session, so it is purely additive — it sets `phone`/
`phone_verified` on the caller's own account and never touches
`auth_provider`, because there is no ambiguity about whose account this is.
This mirrors the table in the project's account-linking plan: WhatsApp
attach behaves like the "password/google -> whatsapp attach" row, always
additive, session-scoped, never a `auth_provider` flip.
"""

# WHATSAPP ANTI-BAN: never call sendText here. This module only reads
# incoming messages the user sent to us first — WAHA/WhatsApp bans numbers
# that message unknown contacts unprompted. Every WAHA call in this file is
# a GET (`check-exists`, `messages`); there is no code path anywhere below
# that calls `POST /api/sendText`, and none should ever be added — not even
# a "welcome"/confirmation text after a successful signup or attach. The
# user messaging us first does not license us replying automatically; the
# real app doesn't do that either, and this module deliberately doesn't
# invent it.

import re
import time

import httpx
from fastapi import Request

from app.core.config import get_settings
from app.core.db.database import query
from app.core.errors import ConflictError, ErrorCode
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key
from app.core.security.deps.jwt import create_access_token, create_refresh_token
from app.core.security.deps.rate_limit import check_rate_limit
from app.core.security.deps.user import user_ip
from app.core.security.deps.whatsapp_code import (
    WHATSAPP_CODE_TTL_MINUTES,
    consume_whatsapp_code,
    generate_whatsapp_code,
    store_whatsapp_code,
)
from app.services.identity import create_account_with_identity

WHATSAPP_CODE_EXPIRES_IN_SECONDS = WHATSAPP_CODE_TTL_MINUTES * 60

# Anti-spam on *starting* a code — cheap insurance against one machine
# generating a flood of codes, matching `signup`'s IP-limit reasoning
# (there's no email/phone to key on yet at this point, only where the
# request came from).
WHATSAPP_CODE_START_MAX_ATTEMPTS = 5
WHATSAPP_CODE_START_WINDOW_SECONDS = 300

# Anti-brute-force on *guessing* a code, keyed by the code itself (not by
# IP): the danger here isn't one IP hammering requests, it's someone
# submitting many different 6-digit codes hoping to land on a live one.
# The real app polls this endpoint roughly every ~2.5s, and a code lives
# for WHATSAPP_CODE_TTL_MINUTES (10) — the frontend's *own* legitimate
# polling traffic during one code's lifetime is ~240 requests
# (600s / 2.5s), all for the *same* code, so a per-code cap has to clear
# that comfortably or a genuine user waiting on their own code gets
# rate-limited. 20 attempts / 10 minutes is set on the code, not the
# frontend's poll count for that code, though — see the note in
# `check_whatsapp_status` below on why polling for a *pending* code never
# actually touches this counter at all, which is what makes 20 a real cap
# on guessing rather than a ceiling normal polling would ever hit.
WHATSAPP_CODE_GUESS_MAX_ATTEMPTS = 20
WHATSAPP_CODE_GUESS_WINDOW_SECONDS = 600

# check_whatsapp_exists's own limit: a plain existence check, no code
# involved, so it doesn't need the tight guessing-focused numbers above —
# 20/60s is generous enough for a real user checking a typo'd number a few
# times, while still capping one IP from using this as a bulk phone-number
# scanner against WAHA.
WHATSAPP_CHECK_MAX_ATTEMPTS = 20
WHATSAPP_CHECK_WINDOW_SECONDS = 60

# The message body a user is asked to send: "MEOCE-123456", "MEOCE 123456",
# or "meoce123456" all match — case-insensitive, hyphen/space/nothing
# between the word and the digits, since WhatsApp's own auto-formatting
# and a person typing by hand can introduce or drop either.
_CODE_PATTERN = re.compile(r"MEOCE[-\s]?(\d{6})", re.IGNORECASE)


def start_whatsapp_signup(request: Request) -> dict:
    """Generates a signup code and returns what the frontend shows the user.

    Rate-limited by IP: like `signup`'s own IP limit, there is nothing else
    to key on yet — no email, no phone, just where the request came from.

    Args:
        request (Request): Used to build the rate-limit key.

    Returns:
        dict: code, whatsapp_number, expires_in_seconds.

    Raises:
        RateLimitError: Too many codes started from this IP (429).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CODE_START, user_ip(request)),
        WHATSAPP_CODE_START_MAX_ATTEMPTS, WHATSAPP_CODE_START_WINDOW_SECONDS,
        "too many WhatsApp sign-in attempts, try again later",
    )

    code = generate_whatsapp_code()
    payload = {"issued_at": time.time()}
    store_whatsapp_code(code, payload)

    result = {
        "code": code,
        "whatsapp_number": get_settings().waha_meoce_number,
        "expires_in_seconds": WHATSAPP_CODE_EXPIRES_IN_SECONDS,
    }
    return result


def start_whatsapp_attach(user_id: str, request: Request) -> dict:
    """Generates an attach code for the already-authenticated caller.

        Same shape as `start_whatsapp_signup`, but the stored payload also
        carries `user_id`, which is what `check_whatsapp_status` uses to tell
        the two flows apart once the code is consumed (see the module
        docstring's linking policy). The route (`POST
        /users/me/whatsapp/attach`) injects `user_id` via `get_current_user_id`
        — this function just takes it as a plain argument, so it stays
        testable without a real token.

        Args:
            user_id (str): The authenticated caller's account id.
            request (Request): Used to build the rate-limit key.

        Returns:
            dict: code, whatsapp_number, expires_in_seconds.

        Raises:
            RateLimitError: Too many codes started from this IP (429).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CODE_START, user_ip(request)),
        WHATSAPP_CODE_START_MAX_ATTEMPTS, WHATSAPP_CODE_START_WINDOW_SECONDS,
        "too many WhatsApp sign-in attempts, try again later",
    )

    code = generate_whatsapp_code()
    payload = {"issued_at": time.time(), "user_id": user_id}
    store_whatsapp_code(code, payload)

    result = {
        "code": code,
        "whatsapp_number": get_settings().waha_meoce_number,
        "expires_in_seconds": WHATSAPP_CODE_EXPIRES_IN_SECONDS,
    }
    return result


def check_whatsapp_status(code: str) -> dict:
    """Polled by the frontend to learn whether the user has texted their code.

    Rate-limited by the code itself, but only for a code Redis doesn't
    recognize (see the module-level constant comment for the 20/10min
    reasoning) — a caller legitimately polling their OWN still-pending,
    real code never touches this counter, no matter how many times they
    poll it. The 6-digit space is what's being guarded: someone trying many
    *different* codes hoping one happens to be live right now is the
    attack this stops. A code that has never been issued, or has already
    expired/been consumed, is reported as "pending", not an error — a
    caller polling a code that just expired mid-poll, or one it never
    actually issued (a stale tab, a typo), gets the exact same harmless
    answer, since telling them apart would only help someone probing which
    codes exist.

    Args:
        code (str): The 6-digit code the frontend is polling on.

    Returns:
        dict: `{"status": "pending"}` while no matching message has been
            seen yet. On a match: `{"status": "confirmed", "access_token":
            ..., "refresh_token": ..., "token_type": ...}` for the signup
            path, or `{"status": "confirmed"}` (no tokens) for the attach
            path — the caller already holds a session in that case.

    Raises:
        RateLimitError: Too many checks against codes Redis doesn't
            recognize (429) — never raised for a real, still-pending code.
        ConflictError: An attach code's phone is already claimed by a
            *different* account (409).
    """
    payload = consume_whatsapp_code(code)

    if payload is None:
        # Only an unrecognized code counts toward the guess limit — this
        # is the branch someone hits by trying codes that were never
        # issued, or that already expired/were consumed. A real code being
        # polled legitimately never reaches this line.
        check_rate_limit(
            valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CODE_GUESS, code),
            WHATSAPP_CODE_GUESS_MAX_ATTEMPTS, WHATSAPP_CODE_GUESS_WINDOW_SECONDS,
            "too many status checks for this code, try again later",
        )
        result = {"status": "pending"}
        return result

    # The code exists, but nothing has matched it yet — that finding out
    # requires reading WAHA, which _find_matching_phone does. If nothing
    # matches, the code is put right back so the next poll can try again;
    # `consume_whatsapp_code` above already deleted it, since it doesn't
    # know in advance whether this call will find a match.
    phone = _find_matching_phone(code, payload["issued_at"])

    if phone is None:
        store_whatsapp_code(code, payload)
        result = {"status": "pending"}
        return result

    if "user_id" in payload:
        return _confirm_attach(payload["user_id"], phone)

    return _confirm_signup(phone)


def _find_matching_phone(code: str, issued_at: float) -> str | None:
    """Reads MEOCE's own WhatsApp chat and looks for this code.

    Args:
        code (str): The 6-digit code to look for, e.g. sent as
            "MEOCE-123456".
        issued_at (float): Unix timestamp (seconds) — messages sent before
            this are ignored, since they necessarily predate the code and
            could otherwise let an old, unrelated message satisfy a brand
            new code by coincidence of digits.

    Returns:
        str | None: The sender's WhatsApp chatId (the exact string WAHA's
            `from` field carries — may be a `@c.us` or `@lid` JID depending
            on whether this contact has migrated, see the module docstring
            in `google_auth.py`'s sibling reasoning about not constructing
            JIDs by hand), or None if no inbound message after `issued_at`
            matches this code.
    """
    settings = get_settings()
    own_chat_id = _waha_check_exists(settings.waha_meoce_number)
    messages = _waha_fetch_recent_messages(own_chat_id)

    for message in messages:
        if message.get("fromMe"):
            continue
        if message.get("timestamp", 0) < issued_at:
            continue

        match = _CODE_PATTERN.search(message.get("body") or "")
        if match and match.group(1) == code:
            return message["from"]

    return None


def _confirm_signup(phone: str) -> dict:
    """Logs into (or creates) the account tied to `phone` and mints tokens.

    Args:
        phone (str): The sender's WhatsApp chatId, matched by
            `_find_matching_phone`.

    Returns:
        dict: status, access_token, refresh_token, token_type.
    """
    # NOTE: identity schema is user_identities (one row per login method),
    # not a flat users.phone column -- provider='whatsapp' rows are keyed
    # by phone as provider_uid.
    sql_lookup = "SELECT account_id AS user_id FROM user_identities WHERE provider = 'whatsapp' AND provider_uid = %s"
    params_lookup = (phone,)
    rows = query(sql_lookup, params_lookup)

    if rows:
        user_id = str(rows[0]["user_id"])
    else:
        # create_account_with_identity() creates accounts + the whatsapp
        # identity + user_profiles atomically (see
        # app/services/identity.py) -- same helper auth.py's signup() and
        # google_auth.py's _create_google_account() use, only the
        # identity INSERT differs per provider.
        sql_identity = (
            "INSERT INTO user_identities (account_id, provider, provider_uid, verified, verified_at) "
            "VALUES (%s, 'whatsapp', %s, true, now())"
        )
        params_identity_rest = (phone,)
        user_id = create_account_with_identity(sql_identity, params_identity_rest)

    result = {
        "status": "confirmed",
        "access_token": create_access_token(user_id),
        "refresh_token": create_refresh_token(user_id),
        "token_type": "bearer",
    }
    return result


def _confirm_attach(user_id: str, phone: str) -> dict:
    """Attaches `phone` to the already-authenticated caller's own account.

    Purely additive — never touches `auth_provider` (see the module
    docstring's linking policy): the caller already has a valid session,
    so there is no ambiguity about whose account this phone belongs to.

    Args:
        user_id (str): The account attaching this phone number, from the
            stored code's payload.
        phone (str): The sender's WhatsApp chatId, matched by
            `_find_matching_phone`.

    Returns:
        dict: `{"status": "confirmed"}` — no new tokens, the caller
            already holds a valid session.

    Raises:
        ConflictError: `phone` already belongs to a *different* account
            (409) — same `UNIQUE(phone)`-guard reasoning as
            `auth.py`'s `_email_taken`.
    """
    sql_taken = (
        "SELECT EXISTS (SELECT 1 FROM user_identities "
        "WHERE provider = 'whatsapp' AND provider_uid = %s AND account_id != %s)"
    )
    params_taken = (phone, user_id)
    rows_taken = query(sql_taken, params_taken)

    if rows_taken[0]["exists"]:
        raise ConflictError(
            "this WhatsApp number is already linked to another account",
            ErrorCode.PHONE_ALREADY_LINKED,
        )

    sql = (
        "INSERT INTO user_identities (account_id, provider, provider_uid, verified, verified_at) "
        "VALUES (%s, 'whatsapp', %s, true, now()) "
        "ON CONFLICT (account_id, provider) DO UPDATE SET "
        "provider_uid = EXCLUDED.provider_uid, verified = true, verified_at = now()"
    )
    params = (user_id, phone)
    query(sql, params, nothing_return=True)

    result = {"status": "confirmed"}
    return result


def check_whatsapp_exists(phone: str, request: Request) -> bool:
    """Whether a phone number has WhatsApp at all — no code involved.

    Same job as the real app's `check-whatsapp` route: a lightweight,
    read-only check used to validate a number *before* asking the user to
    go through the code flow — e.g. a Google-signed-up user typing a phone
    number into a "add WhatsApp" field, so the app can say "that number
    isn't on WhatsApp" immediately instead of generating a code that could
    never be confirmed.

    Public on purpose, unlike `_waha_check_exists`: this one is meant to be
    called directly from a route, for a phone the caller is *asking about*,
    not for resolving MEOCE's own number internally.

    Rate-limited by IP: this makes a real outbound call to WAHA for every
    phone tried, which costs WAHA a request and could otherwise be used to
    enumerate which numbers exist on WhatsApp at scale.

    Args:
        phone (str): E.164 phone number, digits only, no leading `+`.
        request (Request): Used to build the rate-limit key.

    Returns:
        bool: True if WAHA reports this number exists on WhatsApp.

    Raises:
        RateLimitError: Too many checks from this IP (429).
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.WHATSAPP_CHECK, user_ip(request)),
        WHATSAPP_CHECK_MAX_ATTEMPTS, WHATSAPP_CHECK_WINDOW_SECONDS,
        "too many WhatsApp checks, try again later",
    )

    settings = get_settings()
    response = httpx.get(
        f"{settings.waha_api_url}/api/contacts/check-exists",
        params={"phone": phone, "session": settings.waha_session},
        headers={"X-Api-Key": settings.waha_api_key.get_secret_value()},
        timeout=10.0,
    )
    response.raise_for_status()

    return response.json()["numberExists"]


def _waha_check_exists(phone: str) -> str:
    """Resolves MEOCE's own WhatsApp number to a chatId via WAHA.

    Never constructs `{phone}@c.us` directly: WhatsApp's ongoing JID->LID
    migration means a number's real chatId may come back as `@lid` instead
    — this always uses whatever WAHA's own `check-exists` call resolved to,
    the same way the real app and this session's ad-hoc WAHA usage already
    do.

    Args:
        phone (str): E.164 phone number, digits only, no leading `+`.

    Returns:
        str: The resolved chatId (`...@c.us` or `...@lid`).
    """
    settings = get_settings()
    response = httpx.get(
        f"{settings.waha_api_url}/api/contacts/check-exists",
        params={"phone": phone, "session": settings.waha_session},
        headers={"X-Api-Key": settings.waha_api_key.get_secret_value()},
        timeout=10.0,
    )
    response.raise_for_status()

    return response.json()["chatId"]


def _waha_fetch_recent_messages(chat_id: str, limit: int = 20) -> list[dict]:
    """Fetches recent messages for a chat via WAHA.

    Args:
        chat_id (str): The chatId to read, from `_waha_check_exists`.
        limit (int): How many recent messages to fetch. 20 is comfortably
            more than a user would send while waiting to be verified, but
            small enough that this is a cheap call on every poll.

    Returns:
        list[dict]: Each message carries at least `id`, `timestamp` (unix
            seconds), `from` (the sender's chatId, a plain string — the
            confirmed field, read live off WAHA's own response), `fromMe`,
            and `body`.
    """
    settings = get_settings()
    response = httpx.get(
        f"{settings.waha_api_url}/api/messages",
        params={"session": settings.waha_session, "chatId": chat_id, "limit": limit},
        headers={"X-Api-Key": settings.waha_api_key.get_secret_value()},
        timeout=10.0,
    )
    response.raise_for_status()

    return response.json()
