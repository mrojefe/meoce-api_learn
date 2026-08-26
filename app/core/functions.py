"""Helpers that are neither a route, a schema, nor raw database plumbing.

Two things live here:

* `_build_filters` — the WHERE clause shared by a list query and its count.
* `get_enum` — reads the reference tables the API validates against.

They sit together because both are *supporting* work: neither is the database
client itself (that is `app/core/database.py`), and neither belongs to a single
endpoint. Anything added here should pass the same test — used in more than one
place, and not the responsibility of an existing module.
"""

from functools import lru_cache
from typing import Any

from app.core.database import direct_query


def _build_filters(type_ : str | None , sector : str | None) -> tuple[str, tuple[str | None]] :
    """Builds the WHERE clause shared by the page query and the count query.

    A list endpoint asks the database two questions: "give me this page" and
    "how many exist in total". Both must apply *the same* filter, or the client
    receives 14 rows next to a total of 429 and builds a pager for pages that do
    not exist. Written twice, the two clauses drift apart the first time a
    filter is added — so it is written once, here.

    The clause and its parameters are returned together on purpose: the number
    of `%s` in the text must match the number of values in the tuple, exactly
    and in order. Splitting them across two functions would recreate the same
    drift one level down.

    Each filter has the same shape::

        (%s::text IS NULL OR column = %s)

    When the value is None, psycopg sends NULL, `NULL IS NULL` is true and the
    OR short-circuits: no filtering. When a value is given, the left side is
    false and the comparison applies. One switch, two behaviours, and no `if`
    in Python. The `::text` cast is required because Postgres cannot infer the
    type of a bare parameter compared to NULL.

    Note:
        The sector condition references `s.name`, so the caller must alias the
        `sectors` table as `s`. That coupling is the price of sharing the
        clause between two queries; it is deliberate, not an oversight.

    Args:
        type_ (str | None): Instrument type to keep, or None for no filter.
        sector (str | None): Sector name to keep, or None for no filter.

    Returns:
        tuple[str, tuple]: The WHERE clause, and the parameters it expects.

    Examples:
        >>> clause, params = _build_filters("bond", None)
        >>> params
        ('bond', 'bond', None, None)
    """
    filters_types= (type_, type_,sector,sector)
    where_type= """
                    WHERE (%s::text IS NULL OR type = %s) 
                    AND (%s::text IS NULL OR s.name = %s) 
                """ 
    #you can't paste  direclty 
    # psycopg sends the value separately python would paste as text
    # eg : " ... type = %s" % ("stock",) -> type = stock  instead of
    # type == 'stock'

    return where_type,filters_types


@lru_cache
def get_enum(countries : bool = False, sectors : bool = False,
            symbols : bool = False, type_ : bool= False,  ) -> dict[str,Any]:
    """Reads the reference values the API validates against, from the database.

    The lists of sectors, countries and instrument types are facts owned by the
    database, not by Python. Reading them here means a sector added in SQL is
    accepted by the API without editing any code — the alternative, a hardcoded
    list, is a second copy of the truth that silently goes stale.

    The values are returned **exactly** as stored, with no `.upper()` or
    `.strip()`. Normalising them here would create precisely the second truth
    this function exists to avoid: on 2026-08-25 an uppercased copy made every
    response fail validation, because the database holds 'bond' while the enum
    had been taught 'BOND'. Tolerance for the caller's case belongs in
    `make_enum`, not in the stored values.

    Cached with `@lru_cache`: `make_enum` is called once per enum and each call
    asks for every table, so without the cache the same four tables would be
    read three times over. The cache never expires, which changes nothing here
    — the enums it feeds are themselves built once, at import.

    Args:
        countries (bool): Include the `countries` table.
        sectors (bool): Include the `sectors` table.
        symbols (bool): Include every symbol in `instruments`.
        type_ (bool): Include `instrument_types`, returned under the key "types".

    Returns:
        dict[str, list[str]]: One key per requested table, each holding its
            values in database order.

    Examples:
        >>> get_enum(sectors=True)["sectors"][:2]
        ['INDUSTRIELS', 'AGRICULTURE']
    """


    bools = [countries,sectors,symbols,type_]
    tables = ["countries", "sectors", "symbols", "instrument_types" ]
    selected_tables = [table for table, keep in zip(tables, bools) if keep]

    rows = {}
    for table in selected_tables :
   
        match table :
            case "symbols":
                sql =""" SELECT symbol FROM instruments """
                resultat_query = direct_query(sql)
                resultat_query=[rq["symbol"] for rq in resultat_query]
            
            case "instrument_types" :
                sql = """ SELECT code FROM instrument_types """  
                resultat_query = direct_query(sql)
                resultat_query=[rq["code"] for rq in resultat_query]
                table="types"
            
            case _ : 
                sql = f"""SELECT name FROM {table} """
                resultat_query = direct_query(sql)
                resultat_query=[rq["name"]for rq in resultat_query] 

        
        rows.update({f"{table}": resultat_query})

    return rows

    
