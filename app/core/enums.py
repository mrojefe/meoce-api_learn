"""
List of all enum use in the api 
"""


from enum import IntEnum, StrEnum, unique

from app.core.functions import make_enum


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


AllowedType = make_enum("AllowedType", "types",)
AllowedSymbol = make_enum("AllowedSymbol", "symbols",)
AllowedSector = make_enum("AllowedSector", "sectors",)
"""

AllowedSymbol = StrEnum(
    "AllowedSymbol",
    {
        instrument["symbol"]: instrument["symbol"]
        for instrument in INSTRUMENTS
    },
)

in the futur take from the db InstrumentType like:
AllowedSymbol = StrEnum(
    "AllowedSymbol",
    {
        instrument["symbol"]: instrument["symbol"]
        for instrument in INSTRUMENTS
    },
)

"""    