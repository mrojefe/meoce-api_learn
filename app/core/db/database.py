"""PostgreSQL access — one connection pool for the whole application.

The pool is opened once at startup and closed at shutdown (see the lifespan in
main.py). Nothing here knows about HTTP; services call `query()` and get rows.
"""

from contextvars import ContextVar

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.core.config import get_settings

_pool : ConnectionPool | None = None



def conninfo() -> str:
    """Builds the PostgreSQL connection string from the application settings.

    This is the only place the database password is unwrapped from its
    SecretStr. The returned string contains that password in clear text, so it
    must never be logged or included in an error message.

    Returns:
        str: A libpq connection string, e.g.
            "host=127.0.0.1 port=5433 dbname=postgres user=postgres password=..."
    """
    s = get_settings()
    
    connection_info= (
        f"host={s.postgres_host} port={s.postgres_port} dbname={s.postgres_db} "
        f"user={s.postgres_user} password={s.postgres_password.get_secret_value()}"
    )

    return connection_info

def open_pool() -> None:
    """Creates the connection pool. Call once, at application startup.

    `global` is required because the assignment must update the module-level
    `_pool`, not create a local copy.

    Returns:
        None

    Examples:
        >>> open_pool()          # in the lifespan, before the first request
    """
    global _pool
    _pool = ConnectionPool(
        conninfo= conninfo(),
        min_size=1, 
        max_size=5, 
        kwargs={"row_factory": dict_row})



def get_pool() -> ConnectionPool:
    """Returns the open pool.

    Every other module asks for the pool through this function rather than
    importing `_pool` directly, so how it is stored can change in one place.

    Returns:
        ConnectionPool: The pool created by `open_pool()`.

    Raises:
        RuntimeError: If the pool was never opened — which means the
            application did not start correctly.
    """
    if _pool is None:
        raise RuntimeError("pool not opened — did the app start correctly?")
    return _pool
    
def close_pool() -> None:
    """Closes the pool and forgets it. Call once, at application shutdown.

    Without this, connections stay open on the PostgreSQL side after every
    redeploy until the server times them out. Setting `_pool` back to None
    means a later `get_pool()` raises a clear error instead of handing out a
    closed pool.

    Returns:
        None
    """
    global _pool 
    if _pool is not None:
        _pool.close()
        _pool = None

def query(sql: str, params: tuple = (), nothing_return:bool=False) -> list[dict]:
    """Runs a SELECT and returns every row.

    The connection is borrowed from the pool and given back when the `with`
    block ends, including when an exception is raised. Rows arrive as dicts
    because the pool sets `row_factory=dict_row`.

    Values must always be passed through `params`, never formatted into `sql`
    with an f-string: psycopg sends the query and the values separately, so a
    value can never be read as SQL.

    Args:
        sql (str): The statement, with `%s` placeholders for every value.
        params (tuple, optional): Values for the placeholders, in order.
            A single value needs a trailing comma: `("SNTS",)`.

    Returns:
        list[dict]: One dict per row; an empty list if nothing matched.

    Examples:
        >>> query("SELECT symbol FROM instruments WHERE type = %s LIMIT 2", ("bond",))
        [{'symbol': 'AFD.O1'}, {'symbol': 'BABS.O1'}]
    """
    with get_pool().connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        
        if nothing_return :
            return None

        return cur.fetchall()        

def direct_query(sql: str, params: tuple | None = None, nothing_return=False) -> list[dict]:
    """Runs one SELECT on its own short-lived connection, outside the pool.

    `query()` in app/core/database.py is the normal way to reach the database.
    This function exists for the one case `query()` cannot serve: code that runs
    at **import time**, before the application starts and therefore before the
    pool is opened by the lifespan. Building the reference enums is that case.

    Because it opens and closes a connection on every call, it is far more
    expensive than the pool. Use it only for the handful of queries that happen
    once at startup — never inside a request.

    Args:
        sql (str): The statement. Values must be passed as `%s` placeholders,
            never formatted into the string.
        params (tuple | None): Values for the placeholders, in order.

    Returns:
        list[dict]: Every row, one dict per row (`dict_row` row factory).

    Examples:
        >>> direct_query("SELECT name FROM sectors LIMIT 1")
        [{'name': 'INDUSTRIELS'}]
    """
    s = get_settings()

    psycopg_connector = psycopg.connect(
        host = s.postgres_host,
        port = s.postgres_port,
        dbname = s.postgres_db,
        user = s.postgres_user,
        password =  s.postgres_password.get_secret_value(),
        row_factory = dict_row, 
    ) 

    with psycopg_connector, psycopg_connector.cursor() as cur:
        cur.execute(sql, params)

        if nothing_return:
            return None

        rows = cur.fetchall()

    return rows




_current_actor: ContextVar[str | None] = ContextVar("meoce_current_actor", default=None)


def set_current_actor(user_id: str | None) -> None:
    """Records who the current request belongs to.

    A plain module-level variable would not do: two requests run at the same
    time, and the second would overwrite the first. Measured — with a global,
    a request for alice was written under bob's name. A ContextVar keeps one
    value per request, so each sees only its own.

    Not yet used. It exists for attribution — answering "who wrote this row?",
    which Postgres cannot answer on its own because every request reaches it
    as `user=postgres` through the pool.

    Args:
        user_id (str | None): The authenticated user, or None to clear it.
            Clearing matters: threads are reused, so an anonymous request that
            inherited a previous user's id would attribute their write to
            someone who never made it.
    """
    _current_actor.set(user_id)

def get_current_actor() -> str | None:
    """Returns the user the current request belongs to, or None if anonymous."""
    return _current_actor.get()