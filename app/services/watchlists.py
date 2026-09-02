"""Watchlists service — the data and the rules. Knows nothing about HTTP.

The first service in this API handling data that belongs to somebody. Every
function here takes `user_id` as its first argument, and every query uses it.

That is not a convention for tidiness: it is the *only* thing standing between
one user and another's data. Connecting as `postgres` means Row Level Security
does not filter anything (ADR-0001), so a forgotten `WHERE user_id = %s` does
not return an empty list — it returns everybody's rows.
"""

from app.core.db.database import query


def list_watchlists(user_id: str) -> tuple[list[dict], int]:
    """Lists the watchlists belonging to one user.

    `user_id` comes from a verified token, never from the request. A caller
    cannot ask for someone else's lists because there is no way to express the
    question: the id is not a parameter of this endpoint.

    Note what is not returned: `user_id` itself. It is used to filter and then
    dropped — the caller already knows who they are, and a response model is a
    decision about what to expose rather than a copy of the table.

    Ordered by name, which is the only ordering that means anything here: a
    user reads their lists by name, not by when they were created.

    Args:
        user_id (str): The authenticated caller's id, from the token.

    Returns:
        tuple[list[dict], int]: The rows, and how many there are. No pagination
            — nobody has thousands of watchlists, so the count is simply the
            length. Unlike the instruments list, where the total and the page
            size genuinely differ.

    Examples:
        >>> list_watchlists("c028c759-5fee-402b-a09f-ef39f3c22f31")
        ([{'id': '...', 'name': 'look', 'description': None, 'is_public': False}], 1)
    """
    rows = query(
        """
        SELECT id, name, description, is_public, created_at, updated_at
        FROM watchlists
        WHERE user_id = %s
        ORDER BY name
        """,
        (user_id,),
    )
    return rows, len(rows)
