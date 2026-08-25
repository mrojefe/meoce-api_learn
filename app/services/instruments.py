"""Instruments service — the data and the rules. Knows nothing about HTTP."""

from app.core.errors import NotFoundError, ConflictError
from app.core.database import query
from app.core.constant import INSTRUMENTS

from app.core.database import get_pool



def _build_filters(type_ : str | None ) -> tuple[str, tuple[str | None]] :

    filters_types= (type_, type_)
    where_type= "WHERE (%s::text IS NULL OR type = %s)" 
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
    where_sql, where_params = _build_filters(type_)

    sql_rows = """
        SELECT symbol, name, type, status
        FROM instruments
        """  + where_sql + """
        ORDER BY symbol LIMIT %s            
        """
    sql_total = """
        SELECT count(*)
        FROM instruments
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
