"""Preferences service — one row per user, created on first read.

`user_preferences.user_id` is the primary key itself: same "natural key,
no separate id" shape as `user_instrument_flags`. Unlike flags, though, every
user has exactly one row (or should), which is why GET creates it if missing
instead of returning an empty result.
"""

from app.core.db.database import query


def get_preferences(user_id: str) -> dict:
    """Returns the caller's preferences, creating them with defaults if this
    is their first time.

    Unlike `resolve_entitlements` falling back to the free plan without
    writing anything, this DOES write — the row itself is the "first login"
    marker, and every later PATCH needs a row already there to update.

    The defaults (XOF / fr / 1D / candlestick) are not written here — they
    are `DEFAULT` values on the columns themselves
    (`supabase/migrations/20260903193642_user_preferences_db_defaults.sql`).
    `INSERT INTO user_preferences (user_id)` supplies only what is actually
    known — who — and the database fills in the rest, so the defaults exist
    in exactly one place instead of needing to match a Python copy.

    Args:
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict: Every column of `user_preferences` for this user.

    Examples:
        >>> get_preferences(uid)
        {'user_id': ..., 'default_currency': 'XOF', ...}
    """
    sql_select = "SELECT * FROM user_preferences WHERE user_id = %s"
    params_select = user_id
    rows_selected = query(sql_select, (params_select,))

    if  rows_selected :
        rows = rows_selected

    else :

        sql_create = "INSERT INTO user_preferences (user_id) VALUES (%s) RETURNING *"
        params_create = user_id
        rows_first_connexion = query(sql_create, (params_create,))
        rows = rows_first_connexion


    return rows[0]


def update_preferences(user_id: str, fields: dict) -> dict:
    """Sets whichever preference columns the caller sent, creating the row
    first if this is their first write.

    `fields` already holds only what the route decided was actually sent —
    same principle as `update_watchlist`, but the filtering happens in the
    route this time (`payload.model_dump(exclude_unset=True)`) rather than
    threading a separate `fields_set` through, since with 13 possible columns
    that would be 13 extra parameters.

    One `INSERT ... ON CONFLICT (user_id) DO UPDATE` handles both cases —
    first-time write and later edit — the same reasoning as `upsert_flag`:
    `user_id` is the table's own primary key, so the database already knows
    which one this is.

    Args:
        user_id (str): The authenticated caller, from the token.
        fields (dict): Column name -> new value, only for columns the caller
            actually sent. Empty means nothing to change.

    Returns:
        dict: The row as it now stands, every column.

    Examples:
        >>> update_preferences(uid, {"default_currency": "USD"})
        {'default_currency': 'USD', 'default_language': 'fr', ...}
    """
    if not fields:
        return get_preferences(user_id)

    columns = list(fields.keys())
    values = list(fields.values())

    all_columns = ["user_id", *columns]
    insert_columns = ", ".join(all_columns)

    all_placeholders = ["%s"] * (len(columns) + 1)
    insert_placeholders = ", ".join(all_placeholders)

    update_clause_parts = [f"{column} = EXCLUDED.{column}" for column in columns]
    update_clause = ", ".join(update_clause_parts)

    sql_upsert = f"""
        INSERT INTO user_preferences ({insert_columns})
        VALUES ({insert_placeholders})
        ON CONFLICT (user_id)
        DO UPDATE SET {update_clause}, updated_at = now()
        RETURNING *
        """
    params_upsert = (user_id, *values)

    rows = query(sql_upsert, params_upsert)

    return rows[0]
