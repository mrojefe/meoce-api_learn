"""Instrument flags service — a colour+note a user pins to one instrument.

Unlike watchlists, there is no separate "flags list" resource: the primary
key of `user_instrument_flags` is `(user_id, instrument_id)` itself — a
natural key. One user, one instrument, at most one flag. No id to create
first, and therefore no ownership check needed either: the WHERE clause
that finds "your" flag is the same clause that finds it at all.
"""

from app.core.db.database import query
from app.services.instruments import get_instrument_id


def list_flags(user_id: str) -> dict[str, dict]:
    """Lists every flag the caller has set, keyed by symbol.

    A JOIN back to `instruments` is unavoidable: the table stores
    `instrument_id`, but nobody outside the database thinks in ids —
    the caller wants "SNTS", not a uuid.

    Args:
        user_id (str): The authenticated caller, from the token.

    Returns:
        dict[str, dict]: `{"SNTS": {"flag_color": "red", "notes": None}, ...}`.
            A dict rather than a list: symbols are unique per user (the
            primary key guarantees it), so keying by symbol saves the client
            a linear search when it only wants one instrument's flag.

    Examples:
        >>> list_flags("c028c759-5fee-402b-a09f-ef39f3c22f31")
        {'SNTS': {'flag_color': 'red', 'notes': 'watch earnings'}}
    """
    sql_flags = """
        SELECT i.symbol, f.flag_color, f.notes
        FROM user_instrument_flags AS f
        LEFT JOIN instruments AS i ON i.id = f.instrument_id
        WHERE f.user_id = %s
        """
    parms_flag = user_id
    rows = query(sql_flags, (parms_flag,))

    all_flags_by_symbol ={row["symbol"]: {
        "flag_color": row["flag_color"], 
        "notes": row["notes"]
        } for row in rows
        }
    
    return all_flags_by_symbol


def upsert_flag(user_id: str, symbol: str, flag_color: str, notes: str | None) -> dict:
    """Sets the caller's flag on one instrument — creates it, or overwrites it.

    One function, not two. `(user_id, instrument_id)` is the table's own
    primary key, so the database already knows whether a row is there:
    `ON CONFLICT (user_id, instrument_id) DO UPDATE` inserts if it's the
    first flag, and overwrites if one already existed — no need to ask
    first, unlike `_require_ownership` in watchlists, where "does this exist,
    and is it mine" genuinely are two separate questions.

    Args:
        user_id (str): The authenticated caller, from the token.
        symbol (str): The instrument's ticker, already normalised.
        flag_color (str): One of red/orange/yellow/green/blue, enforced by
            the schema's pattern — never trusted raw here.
        notes (str | None): Optional free text.
        nb : EXCLUDED help take the value with past before the  ON CONFLICT

    Returns:
        dict: {"flag_color": ..., "notes": ...} — the flag as it now stands.

    Raises:
        NotFoundError: No instrument has this symbol (404).

    Examples:
        >>> upsert_flag(uid, "SNTS", "red", None)
        {'flag_color': 'red', 'notes': None}
    """
    instrument_id = get_instrument_id(symbol) 

    sql_upsert = """
        INSERT INTO user_instrument_flags (user_id, instrument_id, flag_color, notes)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (user_id, instrument_id)
        DO UPDATE SET flag_color = EXCLUDED.flag_color, notes = EXCLUDED.notes
        RETURNING flag_color, notes
        """
    params_upsert = (user_id, instrument_id, flag_color, notes)

    rows = query(sql_upsert, params_upsert)

    return rows[0]


def delete_flag(user_id: str, symbol: str) -> None:
    """Removes the caller's flag from one instrument, if there is one.

    No error if there wasn't one — same reasoning as
    `remove_watchlist_symbol`: a symbol with no flag on it is already the
    state the caller asked for, so this returns quietly instead of raising.
    Contrast `delete_watchlist`, where a missing *list* IS an error — there
    the caller named something specific expected to exist.

    Args:
        user_id (str): The authenticated caller, from the token.
        symbol (str): The instrument's ticker, already normalised.

    Raises:
        NotFoundError: No instrument has this symbol (404) — the symbol
            itself must exist, even if no flag was ever set on it.
    """
    instrument_id = get_instrument_id(symbol)

    sql_delete = """
        DELETE FROM user_instrument_flags
        WHERE user_id = %s AND instrument_id = %s
        """
    params_delete = (user_id, instrument_id)

    query(sql_delete, params_delete, nothing_return=True)
