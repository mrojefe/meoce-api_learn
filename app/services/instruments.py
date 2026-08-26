"""Instruments service — the data and the rules. Knows nothing about HTTP."""

from app.core.constant import INSTRUMENTS
from app.core.database import query
from app.core.errors import ConflictError, NotFoundError


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


def list_instruments(type_ : str | None = None, sector: str | None = None,
                     limit : int | None = 20) -> tuple[list[dict], int]:
    """Lists instruments, optionally filtered by type.

    Filtering, ordering and limiting all happen in SQL, so the database never
    builds rows that are thrown away. The rows are ordered by symbol, which is
    what makes `limit` meaningful: the same first N on every call.

    An empty result is not an error — "no instrument matches this filter" is a
    valid answer, and the caller receives an empty list with a count of 0.

    Args:
        type_ (str | None): Instrument type — "stock", "index", "bond",
            "right" or "sukuk". None means no filter. Named with a trailing
            underscore because `type` is a Python builtin.
        sector (str | None): Not implemented yet — the sector name lives in the
            `sectors` table and needs a JOIN (module 08).
        limit (int): Maximum number of rows to return.

    Returns:
        tuple[list[dict], int]: The rows, and how many existe in total for the filters apply.

    Examples:
        >>> list_instruments(type_="bond", limit=2)
        ([{'symbol': 'AFD.O1','name': 'AFD 5.25% 2008-2016', 'type': 'bond','status': 'delisted'},
        {'symbol': 'BABS.O1',   'name': 'GSS BAOBAB 6,80% 2024-2029', 'type': 'bond',  'status': 'active'}],
        332)
        
    """
    where_sql, where_params = _build_filters(type_,sector)

    sql_rows = """
        SELECT  
            i.symbol, i.name, i.type, 
            i.status ,s.name as sector
        FROM instruments AS i
        LEFT JOIN  sectors AS s
            ON  s.id = i.sector_id
        """  + where_sql +  """ 
        ORDER BY symbol LIMIT %s            
        """

    #JOIN LEFT because the most importante is to keep symbol 
    # if the drop it's not clearly say by a filter from user
        
    sql_total = """
        SELECT count(*)
        FROM instruments
        LEFT JOIN  sectors AS s
            ON  s.id = instruments.sector_id
        """+ where_sql      

    rows = query(sql_rows,(*where_params,limit))
    total = query(sql_total,(*where_params,))[0].get("count")



    return rows ,int(total)

def get_by_symbol(symbol: str) -> dict:
    """Fetches one instrument by its BRVM symbol.

    The lookup is case-insensitive and tolerant of surrounding spaces: the
    symbol is stripped and uppercased before querying, so "  snts " finds SNTS.

    Args:
        symbol (str): BRVM ticker, e.g. "SNTS" or "BOAB.DA1".

    Returns:
        dict: The instrument — symbol, name, type, country_code, status.

    Raises:
        NotFoundError: If no instrument carries that symbol. The router turns
            it into a 404 in the error contract; this function knows nothing
            about HTTP.

    Examples:
        >>> get_by_symbol("abjc")
        {'symbol': 'ABJC', 'name': "SERVAIR ABIDJAN COTE D'IVOIRE", ...}
    """
    symbol =  symbol.upper().strip()
    rows = query( 
        """
        SELECT symbol, name, type, country_code, status
        FROM instruments
        WHERE (symbol = %s)
        ORDER BY symbol            
        """,
        (symbol, ),
    )
    if not rows:             
        raise  NotFoundError("this symbol doesn't exist") 
        
    return rows[0] # response_model in route gey_by_symbol  is waiting for Envelope[Instrument]    





def create_instrument(symbol: str, name: str, type_: str,
                      sector: str | None = None) -> dict:
    """Creates an instrument.

    NOT YET MIGRATED to the database: this still appends to the in-memory
    INSTRUMENTS list, so anything created here disappears when the server
    restarts. It becomes an SQL INSERT in module 08.

    Args:
        symbol (str): BRVM ticker. Already normalised by the InstrumentCreate
            schema (stripped and uppercased) before it arrives here.
        name (str): Full instrument name.
        type_ (str): "stock", "index", "bond", "right" or "sukuk".
        sector (str | None): Sector name, optional.

    Returns:
        dict: The created instrument.

    Raises:
        ConflictError: If an instrument with that symbol already exists. The
            router turns it into a 409.
    """
    new_instrument = {
                  "symbol":symbol , 
                  "name":name,
                  "type":type_,
                  "sector":sector
                  }
    for instrument in INSTRUMENTS:
        if instrument["symbol"] == new_instrument["symbol"]:
            raise ConflictError("This instrument already exist")

           
    INSTRUMENTS.append(new_instrument)
    return   new_instrument
