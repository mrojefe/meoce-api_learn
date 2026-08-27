"""Instruments service — the data and the rules. Knows nothing about HTTP."""

from psycopg.errors import UniqueViolation

from app.core.database import query
from app.core.enums import AllowedSort
from app.core.errors import ConflictError, NotFoundError
from app.core.functions import _build_filters


def _order_by(sort: AllowedSort | None) -> str:
    """Builds the ORDER BY clause from an already-validated sort column.

    The only f-string in this file that reaches SQL, and the only one allowed.
    A column name cannot be a `%s` parameter — values travel to the server
    separately from the statement, identifiers are part of it — so the name has
    to be written into the text. What makes that safe is where it comes from:
    never the caller's string, only `AllowedSort`, a handful of literals typed
    by hand in app/core/enums.py. Anything else was refused as a 422 by the
    schema long before this function runs.

    Every order ends with `symbol` as a tie-breaker. Without one the sort is
    not deterministic: 375 instruments share a type, and Postgres may return
    those in any sequence, so page 2 can repeat rows from page 1 or skip them
    entirely — silently. `symbol` is unique, which makes the order total and
    pagination honest.

    Columns are qualified with the `i` alias because `instruments` and
    `sectors` both have a `name`; unqualified, Postgres refuses it as
    ambiguous.

    Args:
        sort (AllowedSort | None): The validated column, or None for the
            default order by symbol.

    Returns:
        str: An ORDER BY clause, e.g. "ORDER BY i.type, i.symbol".

    Examples:
        >>> _order_by(None)
        'ORDER BY i.symbol'
        >>> _order_by(AllowedSort.TYPE)
        'ORDER BY i.type, i.symbol'
    """
    if sort is None or sort is AllowedSort.SYMBOL:
        return "ORDER BY i.symbol"
    return f"ORDER BY i.{sort.value}, i.symbol"


def list_instruments(type_ : str | None = None, sector: str | None = None,
                     limit : int | None = 20, offset: int = 0,
                     sort: AllowedSort | None = None) -> tuple[list[dict], int]:
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
        sector (str | None): Sector name, e.g. "INDUSTRIELS". None means no
            filter. Reached through a LEFT JOIN on `sectors`, and filtered in
            SQL — never in Python, or `limit` would cut before the filter ran.
        limit (int): Maximum number of rows to return.

    Returns:
        tuple[list[dict], int]: The rows, and the **total** number matching the
            filters — not the number returned. A client needs the total to
            build a pager; the number returned it can count itself.

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
        """  + where_sql + f"""
        {_order_by(sort)}
        LIMIT %s OFFSET %s
        """

    #JOIN LEFT because the most importante is to keep symbol 
    # if the drop it's not clearly say by a filter from user
        
    sql_total = """
        SELECT count(*)
        FROM instruments
        LEFT JOIN  sectors AS s
            ON  s.id = instruments.sector_id
        """+ where_sql      

    rows = query(sql_rows,(*where_params,limit,offset))

    total = query(sql_total,(*where_params,))[0].get("count")



    return rows ,int(total)

def get_by_symbol(symbol: str, exchange: str | None = None) -> dict:
    """Fetches one instrument by its symbol, and optionally its exchange.

    Case and spacing are already handled: `Symbol` and `AllowedExchange`
    normalise them in the schema, so this function receives canonical values
    and does not repeat the work.

    A symbol is only unique **per exchange** — the table's unique constraint is
    on (exchange_id, symbol) — so the same ticker may legitimately exist on the
    BRVM and on the NGX. When the caller does not say which, and several match,
    this refuses with a 409 naming the exchanges rather than returning an
    arbitrary one. For market data a silently wrong exchange is a wrong price,
    which is worse than an inconvenient error (exercise E-20).

    Args:
        symbol (str): Ticker, e.g. "SNTS" or "BOAB.DA1". Case-insensitive.
        exchange (str | None): Exchange code, e.g. "BRVM" or "NGX". None means
            no filter, which is safe while a symbol is unambiguous.

    Returns:
        dict: The instrument — symbol, name, type, country_code, status and
            exchange_id. The response model drops what it does not declare.

    Raises:
        NotFoundError: No instrument carries that symbol (404).
        ConflictError: The symbol exists on several exchanges and none was
            given (409). The message names them, so the caller can retry.

    Examples:
        >>> get_by_symbol("abjc")
        {'symbol': 'ABJC', 'name': "SERVAIR ABIDJAN COTE D'IVOIRE", ...}
        >>> get_by_symbol("boab", exchange="NGX")
        {'symbol': 'BOAB', ...}
    """
    where_sql ="""WHERE (symbol = %s) 
                AND  (
                 %s::text IS NULL OR
                exchange_id = (SELECT id FROM exchanges WHERE code = %s)
                )""" # %s::text IS NULL OR , help don't have a bug if exchange is None
    
    rows = query( 
        """
        SELECT symbol, name, type, country_code, status ,exchange_id
        FROM instruments
        """ + where_sql + """
        ORDER BY symbol
        """,           
        
        (symbol,exchange,exchange ),
    )# we can take exchange_id , the response_model will throw it away,anyway!

    if not rows:             
        raise  NotFoundError("this symbol doesn't exist") 
    if (len(rows) >= 2) :

        rows_exchange_id = list({row["exchange_id"] for row in rows})  # set: unique values
        
        raw_existing_exchanges=query(""" SELECT code FROM exchanges WHERE id = ANY(%s) """,
                                    (rows_exchange_id,)
                                    )
        existing_exchanges = [row["code"] for row in raw_existing_exchanges]

        raise ConflictError(
            f"{symbol} exists on {len(rows)} exchanges "
            f"({', '.join(existing_exchanges)}) — specify one with ?exchange="
        )
        
    return rows[0] # response_model in route gey_by_symbol  is waiting for Envelope[Instrument]    





def create_instrument(symbol: str, name: str, type_: str,
                    exchange: str , sector: str,
                    currency_code: str | None = None) -> dict:
    """Inserts an instrument and returns the row the database wrote.

    The caller supplies names — "INDUSTRIELS", "BRVM" — while the table stores
    identifiers. Rather than look each one up in Python and pass the id along,
    the INSERT resolves them itself with scalar subqueries. If a name matches
    nothing the subquery yields NULL, the NOT NULL constraint refuses the whole
    statement, and no partial row survives.

    `currency_code` is optional and defaults to the currency of the exchange:
    an instrument listed on the NGX is priced in NGN unless stated otherwise.
    The override exists because reality is messier than the rule — a Eurobond
    can be listed on the BRVM and quoted in USD.

    Duplicates are decided by the database, not here. A prior SELECT would be
    wrong twice: it loses the race (two requests can both find nothing and both
    insert), and it uses the wrong definition — the unique constraint is on
    (exchange_id, symbol), so the same ticker on two exchanges is legitimate.
    Catching UniqueViolation is checked atomically and uses the real rule.

    RETURNING gives back what was actually stored, including the columns the
    database filled in itself, rather than echoing the request back.

    Args:
        symbol (str): Ticker, already normalised by `Symbol` in the schema.
        name (str): Full instrument name.
        type_ (str): One of the values in `instrument_types`, e.g. "stock".
        exchange (str): Exchange code, e.g. "BRVM" or "NGX". Required — a
            default would silently list NGX instruments on the BRVM.
        sector (str): Sector name, e.g. "INDUSTRIELS".
        currency_code (str | None): ISO code. None means "use the exchange's
            currency".

    Returns:
        dict: The inserted row — symbol, name, type, sector_id, exchange_id,
            currency_code.

    Raises:
        ConflictError: That symbol already exists **on that exchange** (409).

    Examples:
        >>> create_instrument("TESTX", "Test", "stock", "NGX", "INDUSTRIELS")
        {'symbol': 'TESTX', 'currency_code': 'NGN', ...}
    """

    #currency_code must stay the last to drop easly and neme is standrdize here           
    new_instrument = (symbol, name.upper(),
                     type_, sector, exchange, currency_code )

    
    sql_defaut_curruency_code = """ SELECT currency_code FROM exchanges WHERE code = %s  """
    params_default_currency_code = (exchange,) if isinstance(exchange,str) else None
   
    # create tuple from new_instrument,respect the order and without 'currency_code'   
    params_add_symbol= new_instrument[:-1]
    sql_add_symbol = """ 
            INSERT INTO instruments(symbol,name,type,sector_id,exchange_id,currency_code)
            VALUES  (%s, %s,%s,
                    (SELECT id FROM sectors WHERE name = %s),
                    (SELECT id FROM exchanges WHERE code = %s), 
                    %s) 
            RETURNING symbol,name,type,sector_id,exchange_id,currency_code ,status       
        """
    
 
    # nb: query return always  list of dict eg:for  exchange NGX ,
    #without query(...)[0]["currency_code"] we got [{'currency_code': 'NGN'}]

    if  currency_code is None :
        #add currency_code from the default
        defaut_currency_code =  query(
                    sql_defaut_curruency_code,
                    params_default_currency_code
                )[0]["currency_code"]

        params_add_symbol+=  (defaut_currency_code,) 

    elif isinstance(currency_code, str) :
        params_add_symbol += (currency_code,)

    try :
        new_instrument = query( sql_add_symbol, params_add_symbol )[0]        
    except UniqueViolation:
        raise ConflictError("This instrument already exist")
                                        
    return   new_instrument
