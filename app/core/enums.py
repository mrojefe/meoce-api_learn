"""
List of all enum use in the api 
"""


from enum import IntEnum, StrEnum, unique


@unique
class ErrorStatus(IntEnum):
    """ All status code stay here """

    OK = 200                  # Read succeeded
    CREATED = 201             # Resource created
    NO_CONTENT = 204          # Done; nothing to return
    BAD_REQUEST = 400         # Malformed request
    UNAUTHORIZED = 401        # Not authenticated
    FORBIDDEN = 403           # Authenticated, but not allowed
    METHOD_NOT_ALLOWED = 405  # Method not autorized 
    NOT_FOUND = 404           # Resource does not exist
    CONFLICT = 409             # Conflict with current state
    UNPROCESSABLE_ENTITY = 422  # Data breaks a business rule
    TOO_MANY_REQUESTS = 429   # Too many requests
    INTERNAL_SERVER_ERROR = 500  # Unexpected server error

@unique
class ErrorCode(StrEnum):   
    """ All error code stay here """

    INTERNAL = "internal_error"
    VALIDATION= "validation_error"
    CONFLICT= "conflict_with_current_state"
    NOT_FOUND= "resource_does_not_exist"
    METHOD_NOT_ALLOWED= "resource_does_not_have_this_method"
    HTTP_ERROR="http_error"


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
