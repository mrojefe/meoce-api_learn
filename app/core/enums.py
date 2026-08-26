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
