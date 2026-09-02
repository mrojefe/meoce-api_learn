"""The domain vocabulary: what values this API accepts for its reference fields.

Instrument types, sectors, exchanges, currencies, and the columns a list may be
sorted by. Each mirrors a reference table, and `tests/test_reference_data.py`
fails if a list here and its table ever disagree.

Kept apart from `errors.py`, which holds the *error* vocabulary. Both were once
in one `enums.py`; they share a Python construct and nothing else.
"""

from enum import StrEnum, unique
from functools import lru_cache
from typing import Any

from app.core.db.database import direct_query


class ReferenceStrEnum(StrEnum):
    """Base for enums that mirror a reference table, tolerant of case.

    The member *name* is ours (upper case, underscores — readable in Python);
    the member *value* is the database's, byte for byte. Only the value is ever
    compared to a row or serialised into a response, so the two never diverge.

    `_missing_` is called by Python whenever a value matches no member, which
    is how "bond", "BOND" and " Bond " all resolve to the same member without a
    second, differently-cased copy of the values existing anywhere.
    """

    @classmethod
    def _missing_(cls, value):
        """Resolves a value ignoring case and surrounding spaces.

        Args:
            value: Whatever the caller passed. Only strings can match.

        Returns:
            ReferenceStrEnum | None: The matching member, or None — and None is
                what produces the 422 listing the allowed values.
        """
        if isinstance(value, str):
            wanted = value.strip().casefold()
            for member in cls:
                if member.value.casefold() == wanted:
                    return member
        return None


@unique
class AllowedType(ReferenceStrEnum):
    """The instrument types, mirroring the `instrument_types` table.

    Hardcoded on purpose, and kept honest by tests/test_reference_data.py,
    which fails if this list and the table ever disagree.

    Building it from the database at import looked safer and was not: the API
    then refuses to start when the database is unreachable, `/openapi.json`
    advertises different values per environment, and importing a module opens
    connections. A closed set that changes once a year belongs in code; the
    database stays the authority through its foreign keys, and the test is what
    tells you — loudly, in CI — that the copy went stale.
    """

    STOCK = "stock"
    BOND = "bond"
    ETF = "etf"
    SUKUK = "sukuk"
    RIGHT = "right"
    WARRANT = "warrant"
    INDEX = "index"


@unique
class AllowedSector(ReferenceStrEnum):
    """The sectors, mirroring the `sectors` table.

    Same reasoning as AllowedType, and guarded by the same test. Values keep
    the database's exact spelling, spaces included — the member name is the
    only thing allowed to differ.
    """

    INDUSTRIELS = "INDUSTRIELS"
    AGRICULTURE = "AGRICULTURE"
    DISTRIBUTION = "DISTRIBUTION"
    AUTRES = "AUTRES"
    SERVICES_FINANCIERS = "SERVICES FINANCIERS"
    SERVICES_PUBLICS = "SERVICES PUBLICS"
    TELECOMMUNICATIONS = "TELECOMMUNICATIONS"
    TRANSPORT = "TRANSPORT"
    CONSOMMATION_DISCRETIONNAIRE = "CONSOMMATION DISCRETIONNAIRE"
    CONSOMMATION_DE_BASE = "CONSOMMATION DE BASE"
    ENERGIE = "ENERGIE"



@unique
class AllowedExchange(ReferenceStrEnum):
    """The exchanges, mirroring the `exchanges` table (as of 2026-08-26).

    Same reasoning as AllowedType: a closed set that changes when MEOCE opens a
    new market, so it lives in code and the database stays the authority
    through the foreign key. Add a row to `exchanges` and this list must follow.

    Values are the exchange **codes**, exactly as stored, because that is what
    a caller passes as `?exchange=` and what the SQL compares to `code`.
    """
    BRVM = "BRVM"
    NGX = "NGX"


@unique
class AllowedCurrencieCode(ReferenceStrEnum):
    """The currency codes, mirroring the `currencies` table (as of 2026-08-26).

    ISO 4217 codes, as stored. Used when a caller overrides the currency an
    instrument would otherwise inherit from its exchange — a Eurobond listed on
    the BRVM but quoted in USD, for example.

    Note:
        The class name is misspelled: "Currencie" should be "Currency"
        (singular *currency*, plural *currencies*). Worth renaming, but it is a
        rename across several files rather than a docstring fix.
    """
    XOF = "XOF"
    EUR = "EUR"
    NGN = "NGN"
    MAD = "MAD"
    ZAR = "ZAR"
    USD = "USD"


@unique
class AllowedSort(ReferenceStrEnum):
    """The columns a caller may sort the instrument list by.

    NOT a mirror of a table, unlike AllowedType or AllowedSector: "sortable" is
    a smaller idea than "exists". Two rules decide what belongs here.

    First, only columns the client can already see. Sorting by a hidden column
    leaks it — order by a salary nobody may read and you learn who earns most
    without ever seeing a number.

    Second, and this is why the enum exists at all: a column name cannot be a
    `%s` parameter. Values travel to the server separately from the statement;
    identifiers are part of the statement, so the name has to be written into
    the SQL text. Choosing it from this list means the caller's text never
    reaches SQL — it only *selects* one of the strings written here.
    `?sort=symbol; DROP TABLE instruments--` matches no member, so it is a 422
    and no statement is ever built from it.

    This is the one place in the API where validation is the security control
    rather than a convenience. Everywhere else, `%s` is.

    Values are the column names exactly as the table spells them: Postgres
    folds an unquoted identifier to lowercase, but a quoted one it does not, so
    matching the real spelling stays correct either way.
    """

    SYMBOL = "symbol"
    NAME = "name"
    TYPE = "type"
    STATUS = "status"


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
