"""Watchlists service — the data and the rules. Knows nothing about HTTP.

The first service in this API handling data that belongs to somebody. Every
function here takes `user_id` as its first argument, and every query uses it.

That is not a convention for tidiness: it is the *only* thing standing between
one user and another's data. Connecting as `postgres` means Row Level Security
does not filter anything (ADR-0001), so a forgotten `WHERE user_id = %s` does
not return an empty list — it returns everybody's rows.
"""

from uuid import UUID

from app.core.db.database import query
from app.core.errors import ForbiddenError, NotFoundError
from app.schemas.plans import PlanFeatures


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
    sql_select_watchlist = """
        SELECT id, name, description, is_public, created_at, updated_at
        FROM watchlists
        WHERE user_id = %s
        ORDER BY name
        """
    params_select_watchlist= UUID(user_id )   
    rows = query( sql_select_watchlist , (params_select_watchlist,) )
    return rows, len(rows)

def create_watchlist(
    user_id: UUID,
    name: str,
    description: str | None,
    is_public: bool,
    entitlements: PlanFeatures,) -> dict:
    """Creates a watchlist for one user, if their plan still allows another.

    The first limit this API actually enforces. Until now the plans described
    what a user may have and nothing checked it — `max_watchlists` was a number
    in a JSONB column that only the browser ever read, which means it applied
    only to people who did not use curl.

    `None` means unlimited, which is why the check reads the way it does: not
    `count >= limit`, which would refuse everything when the limit is None, but
    an explicit test for None first.

    Args:
        user_id (str): The authenticated caller, and the owner of the new row.
            Never taken from the body, so nobody can create a watchlist inside
            somebody else's account.
        name (str): The list's name. Deliberately not unique — two of your own
            lists may share a name, which is why the API returns the id and the
            client keeps it.
        description (str | None): Optional.
        is_public (bool): Whether others may see it.
        entitlements (PlanFeatures): The caller's plan, resolved by the
            dependency before this function runs.

    Returns:
        dict: The row as the database wrote it — id and timestamps included,
            since those are the database's to decide.

    Raises:
        ForbiddenError: The plan's `max_watchlists` is reached. 403, not 401:
            we know exactly who they are, and a new token would not help.

    Examples:
        >>> create_watchlist(uid, "BRVM banks", None, False, free_plan)
        ForbiddenError: Your plan allows 2 watchlists and you have 2.
    """
    limit = entitlements.max_watchlists

    if limit is not None:
        # Count, then insert — the same shape as the duplicate check we removed
        # from create_instrument, and the same weakness: two requests can both
        # count 1 against a limit of 2 and both insert. Unlike a symbol there is
        # no unique constraint that could catch it, because two watchlists with
        # the same name are legal. Closing it properly needs a per-user lock or
        # a constraint the database can check. Noted, not solved here.
        sql_count = "SELECT count(*) AS total FROM watchlists WHERE user_id = %s"
        current_total = query(sql_count, (user_id,))[0]["total"]

        if current_total >= limit:
            raise ForbiddenError(
                f"Your plan allows {limit} watchlists and you have "
                f"{current_total}. Upgrade to create more.",
            )

    sql_create = """
        INSERT INTO watchlists (user_id, name, description, is_public)
        VALUES (%s, %s, %s, %s)
        RETURNING id, name, description, is_public, created_at, updated_at
        """
    params_create = (user_id, name, description, is_public)

    rows = query(sql_create, params_create)

    return rows[0]

def _require_ownership(user_id: str, watchlist_id: str) -> None:
    """Raises unless this watchlist exists and belongs to this user.

    Extracted from `delete_watchlist` once a second function
    (`remove_item`) needed the exact same check. Two queries, deliberately —
    the same pattern as `get_by_symbol` for an ambiguous exchange: a single
    `WHERE id = %s AND user_id = %s` cannot tell "no such list" apart from
    "yours, but not this one", and the caller wants those to differ (404 vs
    403), so we have to ask first.

    Also what the real API does — `_own_watchlist` in
    `_real_eg/meoce-api/app/api/v1/watchlists.py` runs the same select-then-act
    check before every write on a watchlist.

    Args:
        user_id (str): The authenticated caller.
        watchlist_id (str): The watchlist being acted on.

    Raises:
        NotFoundError: No watchlist has this id (404).
        ForbiddenError: The watchlist exists and belongs to someone else (403).
    """
    sql_owner = "SELECT user_id FROM watchlists WHERE id = %s"
    rows = query(sql_owner, (watchlist_id,))

    if not rows:
        raise NotFoundError("this watchlist doesn't exist")

    # the database returns user_id as a UUID object, not a string
    if rows[0]["user_id"] != UUID(user_id):
        raise ForbiddenError("this watchlist doesn't belong to you")


def delete_watchlist(user_id: str, watchlist_id: str) -> None:
    """Deletes one watchlist, if the caller owns it.

    Args:
        user_id (str): The authenticated caller.
        watchlist_id (str): The list to delete.

    Raises:
        NotFoundError: No watchlist has this id (404).
        ForbiddenError: The watchlist exists and belongs to someone else (403).
    """
    _require_ownership(user_id, watchlist_id)

    sql_delete = "DELETE FROM watchlists WHERE id = %s"
    params_delete = watchlist_id

    query(sql_delete, (params_delete,), nothing_return=True)

def remove_watchlist_symbol(user_id: str, watchlist_id: str, symbol: str) -> None:
    """Removes one instrument from one of the caller's watchlists.

    Three steps, in order, and each can fail for a different reason:

    1. does this watchlist belong to the caller? (`_require_ownership` — the
       same check `delete_watchlist` uses)
    2. what row does this symbol refer to? `watchlist_items` stores
       `instrument_id`, a uuid — the route only ever receives a symbol, so it
       must be resolved before anything else can happen
    3. delete the one row matching both `watchlist_id` and `instrument_id`

    A symbol that is not actually in the list is not an error: removing
    something already absent leaves the world exactly as the caller wanted it,
    so this returns quietly rather than raising. Compare with `delete_watchlist`,
    where a missing *list* IS an error — the caller asked for something specific
    to be gone, and there was nothing there to act on in the first place.

    Args:
        user_id (str): The authenticated caller.
        watchlist_id (str): The list to remove the item from.
        symbol (str): The instrument's ticker, already normalised by the
            `Symbol` type in the schema.

    Raises:
        NotFoundError: No watchlist has this id (404), or the symbol matches no
            instrument (404).
        ForbiddenError: The watchlist exists and belongs to someone else (403).
    """
    _require_ownership(user_id, watchlist_id)

    sql_instrument = "SELECT id FROM instruments WHERE symbol = %s"
    params_instrument = symbol
    rows_instrument = query(sql_instrument, (params_instrument,))

    if not rows_instrument:
        raise NotFoundError(f"no instrument with symbol {symbol!r}")

    instrument_id = rows_instrument[0]["id"]


    sql_remove = """
        DELETE FROM watchlist_items
        WHERE watchlist_id = %s AND instrument_id = %s
        """
    params_remove = (watchlist_id, instrument_id )  

    query(sql_remove, (*params_remove,), nothing_return=True)






