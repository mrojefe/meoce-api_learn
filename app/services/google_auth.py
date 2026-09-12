"""Google OAuth sign-in — a second, independent way to reach an account.

Kept apart from `auth.py`, whose own docstring already calls Google OAuth
"a separate, later flow", not an addition to that module.

**Account-linking policy — "a newly-proven standalone method retires the
previous one":** Google sign-in arrives with no existing session — the
caller presents a Google ID token and nothing else, so there is no way to
know "this is the same person already logged in another way" except by
matching against something already on file. Two things can do that
matching: `google_sub` (Google's own stable per-account id, the token's
`sub` claim) and `email`.

`sub` is checked first and is the durable anchor: once a `users` row has
a `google_sub`, every later sign-in for that same Google account is found
by `sub`, even if the person's Google email address itself has since
changed. `email` is only the fallback for the very first Google sign-in
ever seen for a row — either a brand-new account, or an existing
password/WhatsApp account linking to Google for the first time, where no
`google_sub` has been recorded yet and email is the only thing available
to match on.

When that email already belongs to an account signed up with a password,
Google's own verification is treated as authoritative and the account's
`auth_provider` flips to `'google'`, `password_hash` is cleared. This is
safe specifically because the password reset flow (see
`app/services/auth.py`'s `request_password_reset`/`reset_password`) gives
the user a way back to a password-based login regardless of what
`auth_provider` currently says — losing the password this way is not
losing access to the account. The same rule applies uniformly to a
`'whatsapp'` account with a matching email: the email is authoritative
there too, since there's no session to consult and no other principled
way to decide whose account this newly-verified email belongs to. This is
deliberately "Model A" from the project's account-linking design (see the
plan) — a single `auth_provider` column that names the one
currently-canonical method, not a multi-method join letting one person use
password AND Google AND WhatsApp at once (that's real, correct, future
work, out of scope here).

**Google-as-source-of-truth policy — every field, every sign-in, not just
at creation:** `sub` is the one claim Google guarantees never changes for
a given account, so it's written once and never touched again after that.
Every other claim Google hands back — `email`, `email_verified`,
`given_name`, `family_name`, `picture`, `locale`, `hd` — CAN change on
Google's side at any time (a person can rename themselves, change email,
change photo, switch Workspace domain), so all of those are freshly
overwritten from the token's current contents on *every single*
`google_sign_in` call, not only when the account is first created or
first linked. Google is being treated as the permanent, live source of
truth for its own fields.

One deliberate, accepted consequence of this: `locale` seeds/overwrites
`user_preferences.default_language` on every Google sign-in too. If a
user manually changes their in-app language via Settings and later signs
in with Google again, that manual choice is silently reverted to whatever
their Google account's current locale says. This is the intended tradeoff
of "Google is authoritative for its own fields", not a bug — a future
reader should not "fix" this by making `default_language` sticky against
Google without revisiting the policy first.
"""

from fastapi import Request
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.core.config import get_settings
from app.core.db.database import query
from app.core.errors import ErrorCode, UnauthorizedError
from app.core.reference import StartRateLimitKeyTypes, valide_rate_limite_key
from app.core.security.deps.jwt import create_access_token, create_refresh_token
from app.core.security.deps.rate_limit import check_rate_limit
from app.core.security.deps.user import user_ip

GOOGLE_SIGN_IN_MAX_ATTEMPTS = 10
GOOGLE_SIGN_IN_WINDOW_SECONDS = 60


def google_sign_in(id_token: str, request: Request) -> dict:
    """Verifies a Google ID token and returns a fresh access + refresh pair.

    Creates the account on a first sign-in, links it onto an existing
    password/WhatsApp account with the same email (see the module
    docstring's linking policy), or resyncs a returning Google user's
    profile fields from the token and logs them in — the same
    three-token-pair shape either way, since the caller only ever cares
    that they now hold a valid session.

    Rate-limited by IP, not by email: unlike `login`, there is no email to
    key on before the token is even verified — the only thing known about
    the caller before verification succeeds is where the request came from,
    same reasoning as `signup`'s IP limit.

    Args:
        id_token (str): The Google-issued ID token from the frontend's
            Google Sign-In widget — a JWT signed by Google, not by us.
        request (Request): Used to build the rate-limit key.

    Returns:
        dict: access_token, refresh_token, token_type.

    Raises:
        RateLimitError: Too many attempts from this IP within the window
            (429).
        UnauthorizedError: The token failed Google's own verification
            (expired, wrong audience, forged signature — `google-auth` can
            raise several different exception types for these, and, same
            as `verify_password_match`'s stance, they are deliberately not
            distinguished here) or the token verified but Google itself
            reports the email as unverified (401) — an unverified Google
            email is held to the exact standard already applied to
            password signups.
    """
    check_rate_limit(
        valide_rate_limite_key(StartRateLimitKeyTypes.GOOGLE_SIGN_IN, user_ip(request)),
        GOOGLE_SIGN_IN_MAX_ATTEMPTS, GOOGLE_SIGN_IN_WINDOW_SECONDS,
        "too many sign-in attempts, try again later",
    )

    try:
        payload = google_id_token.verify_oauth2_token(
            id_token, google_requests.Request(), audience=get_settings().google_oauth_client_id,
        )
    except Exception as exc:
        raise UnauthorizedError(
            "invalid or expired Google credential", ErrorCode.GOOGLE_CREDENTIAL_INVALID
        ) from exc

    email_verified = payload.get("email_verified", False)
    if not email_verified:
        raise UnauthorizedError(
            "this Google account's email is not verified", ErrorCode.GOOGLE_EMAIL_NOT_VERIFIED
        )

    user_id = _find_or_link_account(payload)

    return {
        "access_token": create_access_token(user_id),
        "refresh_token": create_refresh_token(user_id),
        "token_type": "bearer",
    }


def _find_or_link_account(payload: dict) -> str:
    """Applies the account-linking policy and returns the account's id.

    Kept separate from `google_sign_in` so that function stays a readable
    top-to-bottom flow (rate-limit, verify, link, mint tokens) while all
    of the branching for "which row, in what state" lives here.

    Looks up by `google_sub` first — the durable anchor, see the module
    docstring — and only falls back to `email` when no row has that `sub`
    yet, since email is the only thing available to match on for a first
    Google sign-in (brand-new account, or an existing password/WhatsApp
    account linking for the first time).

    Args:
        payload (dict): The decoded, already-verified Google ID token.

    Returns:
        str: The `users.id` for this Google sign-in, whether just created,
            just linked, or already there.
    """
    google_sub = payload["sub"]

    rows = query("SELECT id, auth_provider FROM users WHERE google_sub = %s", (google_sub,))

    if not rows:
        rows = query("SELECT id, auth_provider FROM users WHERE email = %s", (payload["email"],))

    if not rows:
        return _create_google_account(payload)

    row = dict(rows[0])
    user_id = str(row["id"])
    auth_provider = row["auth_provider"]

    if auth_provider in ("password", "whatsapp"):
        query(
            "UPDATE users SET auth_provider = 'google', email_verified = true, "
            "password_hash = NULL WHERE id = %s",
            (user_id,),
            nothing_return=True,
        )
    # auth_provider == "google" already: an ordinary returning sign-in,
    # nothing provider-specific to change — _resync_google_fields below
    # still refreshes email/name/picture/locale/hd either way.

    _resync_google_fields(user_id, payload)

    return user_id


def _create_google_account(payload: dict) -> str:
    """Inserts a brand-new account for a Google identity never seen before.

    The `mirror_user_profile` trigger (see
    `supabase/migrations/20260908120000_swap_users_user_profiles_names.sql`)
    fires on this INSERT and creates the matching `user_profiles` row, but
    it only sets `id`/`username` — it derives a username from the email and
    nothing else, so it never touches `first_name`/`last_name`/
    `avatar_url`/`last_login`, and it never touches `user_preferences` at
    all. Those are written here, via `_resync_google_fields` plus a first
    `user_preferences` INSERT, or Google's profile data is silently
    dropped on the floor.

    Args:
        payload (dict): The decoded, already-verified Google ID token.

    Returns:
        str: The new account's id.
    """
    sql_insert = """
        INSERT INTO users (email, auth_provider, email_verified, google_sub, google_hd)
        VALUES (%s, 'google', true, %s, %s)
        RETURNING id
        """
    rows = query(sql_insert, (payload["email"], payload["sub"], payload.get("hd")))
    user_id = str(rows[0]["id"])

    _sync_profile_fields(user_id, payload)

    default_language = _language_from_locale(payload.get("locale"))
    if default_language is not None:
        query(
            "INSERT INTO user_preferences (user_id, default_language) VALUES (%s, %s)",
            (user_id, default_language),
            nothing_return=True,
        )
    # else: no usable locale claim — leave default_language at its DB
    # default (see user_preferences.py's get_preferences docstring), no
    # row to insert here at all since one isn't needed until the first
    # write, same reasoning get_preferences already documents.

    return user_id


def _resync_google_fields(user_id: str, payload: dict) -> None:
    """Refreshes every Google-sourced field except `google_sub` itself.

    Shared by both the linking branch and the plain-returning-google
    branch of `_find_or_link_account` — the "sync everything from Google
    except identity-branch-specific fields" work is identical in both
    cases, only whether `auth_provider`/`password_hash` also change
    differs, and that part is handled by the caller before this runs.

    `google_sub` is deliberately never written here — it's the anchor,
    written once at creation and never touched again (see the module
    docstring).

    Args:
        user_id (str): The account being resynced.
        payload (dict): The decoded, already-verified Google ID token.
    """
    # GOOGLE-AUTHORITATIVE: every field below is overwritten from Google's
    # token on every sign-in, except google_sub (the permanent anchor).
    # This includes silently reverting a user's manually-changed
    # default_language to their current Google locale — intentional, not
    # a bug.
    query(
        "UPDATE users SET email = %s, email_verified = true, google_hd = %s WHERE id = %s",
        (payload["email"], payload.get("hd"), user_id),
        nothing_return=True,
    )

    _sync_profile_fields(user_id, payload)

    default_language = _language_from_locale(payload.get("locale"))
    if default_language is not None:
        query(
            """
            INSERT INTO user_preferences (user_id, default_language)
            VALUES (%s, %s)
            ON CONFLICT (user_id) DO UPDATE SET default_language = EXCLUDED.default_language
            """,
            (user_id, default_language),
            nothing_return=True,
        )
    # else: no usable locale claim on this sign-in — leave whatever
    # default_language is already on file untouched, rather than
    # clobbering a real value with a default.


def _sync_profile_fields(user_id: str, payload: dict) -> None:
    """Writes `user_profiles.first_name`/`last_name`/`avatar_url`/`last_login`
    from the token — the one UPDATE shared by account creation, linking,
    and a plain returning sign-in, since all three need the exact same
    write.

    Args:
        user_id (str): The account being written.
        payload (dict): The decoded, already-verified Google ID token.
    """
    query(
        "UPDATE user_profiles SET first_name = %s, last_name = %s, "
        "avatar_url = %s, last_login = now() WHERE id = %s",
        (payload.get("given_name"), payload.get("family_name"), payload.get("picture"), user_id),
        nothing_return=True,
    )


def _language_from_locale(locale: str | None) -> str | None:
    """Normalizes a Google `locale` claim down to a bare language code.

    Google's `locale` claim looks like `"en-US"`/`"fr-FR"`/sometimes just
    `"en"` — `user_preferences.default_language` only wants the language
    part, not the region, so this takes everything before the first `-`.

    Args:
        locale (str | None): The token's `locale` claim, if present.

    Returns:
        str | None: The bare language code (e.g. `"en"`), or None if
            `locale` was missing/empty — callers leave the column
            untouched (create) or unchanged (resync) in that case rather
            than writing a nonsense value.

    Examples:
        >>> _language_from_locale("en-US")
        'en'
        >>> _language_from_locale("fr")
        'fr'
        >>> _language_from_locale(None)
    """
    if not locale:
        return None

    return locale.split("-")[0]
