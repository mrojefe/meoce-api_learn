"""User profile service — the caller's own row in `user_profiles` joined to
`users`, and nothing else.

`user_profiles` and `users` no longer duplicate any column: `user_profiles`
holds display fields (username, name, bio, avatar, country,
profile_completed), `users` holds identity/credentials (email, phone,
password_hash, auth_provider). This service reads both, joined, because a
profile screen shows fields from both tables — but only `user_profiles`
columns are ever written here (`update_profile` and `update_identity_fields`
both target `user_profiles`; nothing in this file writes `users`).

Every function here takes `user_id` from a verified token. There is no way to
read or edit anyone else's profile: no `{user_id}` ever appears in a URL for
these routes, "me" is the whole point.
"""

from app.core.db.database import query
from app.core.errors import ConflictError


def get_profile(user_id: str) -> dict:
    """Returns the caller's own profile — the fields safe to show them.

    `role` and `account_kind` are left out: those decide what the caller may
    *do* (admin/api_client, real/seed), not something a profile screen shows
    back to them. `status` and `created_at` are included — read-only, but a
    user should be able to see their own account status and join date.
    `last_login` is included too, though nothing writes it yet — it will
    read `null` for everyone until a login flow is built to update it.

    Args:
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: username, email, phone, first_name, last_name, display_name,
            bio, avatar_url, country, profile_completed, last_login,
            created_at, status.

    Examples:
        >>> get_profile(uid)
        {'username': 'jfe', 'email': 'jfe@example.com', ...}
    """
    sql_profile = """
        SELECT u.username, p.email, p.phone, u.first_name, u.last_name,
               u.display_name, u.bio, u.avatar_url, u.country,
               u.profile_completed, u.last_login, u.created_at, u.status
        FROM user_profiles AS u
        JOIN users AS p ON p.id = u.id
        WHERE u.id = %s
        """
    params_profile = user_id
    rows = query(sql_profile, (params_profile,))

    return rows[0]


def update_profile(user_id: str, fields: dict) -> dict:
    """Changes only the profile fields sent.

    Same shape as `update_preferences`: `fields` already holds only what the
    route decided was actually sent. Empty means nothing to change, so no
    UPDATE runs — just the current profile is returned.

    `username` is the one field with a real constraint behind it
    (`UNIQUE(username)`) — a duplicate is caught here and turned into a 409,
    instead of reaching the database as a raw `UniqueViolation`.

    Args:
        user_id (str): The authenticated caller, from the token.
        fields (dict): Column name -> new value, only for columns the caller
            actually sent. Never `email`, `phone`, `role`, `status`,
            `account_kind` — those are not exposed as editable, and `email`/
            `phone` live in `users` (identity), not writable here.

    Returns:
        dict: The profile as it now stands, same shape as `get_profile`.

    Raises:
        ConflictError: The requested `username` is already taken (409).

    Examples:
        >>> update_profile(uid, {"display_name": "JF"})
        {'username': 'jfe', 'display_name': 'JF', ...}
    """
    if not fields:
        return get_profile(user_id)

    if "username" in fields:
        sql_taken = """
            SELECT EXISTS (
                SELECT 1 FROM user_profiles WHERE username = %s AND id != %s
            )
            """
        params_taken = (fields["username"], user_id)
        rows_taken = query(sql_taken, params_taken)
        if rows_taken[0]["exists"]:
            raise ConflictError(f"username {fields['username']!r} is already taken")

    columns = list(fields.keys())
    values = list(fields.values())

    set_clause_parts = [f"{column} = %s" for column in columns]
    set_clause = ", ".join(set_clause_parts)

    sql_update = f"""
        UPDATE user_profiles
        SET {set_clause}, updated_at = now()
        WHERE id = %s
        """
    params_update = (*values, user_id)

    query(sql_update, params_update, nothing_return=True)

    return get_profile(user_id)


def update_identity_fields(user_id: str, fields: dict) -> None:
    """Writes `country`/`profile_completed` to `user_profiles`, and nothing else.

    This is deliberately a separate function from `update_profile`, not an
    extra branch inside it — even though, after the users/user_profiles
    rename, both `update_profile` and this function now target the same
    `user_profiles` (display) table. `update_profile`'s own docstring
    already draws a boundary explicitly ("`email`/`phone` live in `users`,
    not writable here"). `users` is the identity/credentials table — it
    holds `email`, `phone`, `password_hash`, `auth_provider` — so it carries
    a stricter access posture than `user_profiles` (display fields, now
    including `country`/`profile_completed`). Keeping this function apart
    from `update_profile` means each function's
    docstring stays a true, narrow description of what table it touches,
    and whitelisting stays trivial to audit: this function can only ever
    write the two columns named in `_ALLOWED_IDENTITY_FIELDS`, never
    `email`/`phone`/`password_hash`/`auth_provider`, no matter what a caller
    puts in `fields` — those simply are not accepted as schema fields
    upstream, but this function does not rely on that alone; it whitelists
    again here, the same "never trust the caller's dict keys blindly"
    reasoning `update_profile` already applies to `username`/etc.

    Unlike `update_profile`, this function does not return the resulting
    profile. Its caller (the `PATCH /users/me` route) already calls
    `update_profile` and then `get_profile` in the same request to build the
    response, so re-fetching here would just be a wasted query.

    Args:
        user_id (str): The authenticated caller, from the token.
        fields (dict): Column name -> new value. Only `country` and
            `profile_completed` are honored; anything else is silently
            dropped. Empty means nothing to change — no UPDATE runs.

    Returns:
        None.

    Examples:
        >>> update_identity_fields(uid, {"country": "CI"})
        >>> update_identity_fields(uid, {})  # no-op
    """
    _ALLOWED_IDENTITY_FIELDS = {"country", "profile_completed"}
    fields = {k: v for k, v in fields.items() if k in _ALLOWED_IDENTITY_FIELDS}

    if not fields:
        return

    columns = list(fields.keys())
    values = list(fields.values())

    set_clause_parts = [f"{column} = %s" for column in columns]
    set_clause = ", ".join(set_clause_parts)

    sql_update = f"""
        UPDATE user_profiles
        SET {set_clause}
        WHERE id = %s
        """
    params_update = (*values, user_id)

    query(sql_update, params_update, nothing_return=True)
