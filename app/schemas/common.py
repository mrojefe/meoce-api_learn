"""Shapes shared by every endpoint: the envelopes, the meta block, Symbol,
Phone.

Success and failure each have exactly one shape here, so a client writes one
unwrapping function instead of one per endpoint.
"""
import re
from typing import Annotated, Any, Generic, TypeVar

from pydantic import AfterValidator, BaseModel, BeforeValidator, Field
from pydantic_extra_types.phone_numbers import PhoneNumberValidator

Symbol = Annotated[
    str,
    BeforeValidator(lambda v: v.strip().upper() if isinstance(v, str) else v),
    Field(min_length=2, max_length=12, pattern=r"^[A-Z0-9. \-]+$",
    description='BRVM ticker, uppercase - "Snts" becomes "SNTS"',
    examples=["SNTS"])
]    
"""A BRVM ticker.

Deliberately NOT an Enum built from the database. The set of symbols is open:
it grows every time an instrument is listed, so an enum frozen at startup would
reject a symbol this very API had just created - until a restart. A pattern
describes the shape of a valid symbol without claiming to know every one that
exists. Enums are for closed sets: the types, the sectors.
"""


Phone = Annotated[
    str,
    PhoneNumberValidator(number_format="E164", default_region="CI"),
    AfterValidator(lambda v: v.lstrip("+")),
]
"""A real, parseable phone number -- validated by the `phonenumbers` library
(https://pydantic.dev/docs/validation/latest/api/pydantic-extra-types/pydantic_extra_types_phone_numbers/),
not a bare `str`. A route that declares `phone: str` accepts literally any
text -- "not a phone", empty, whatever -- and the first place that would ever
notice is a failed WAHA call three layers down. This type rejects garbage at
the boundary (422, before any service code runs) and normalises whatever
shape it accepts ("+225...", "225...", a local "07...") to this codebase's
existing convention: digits only, no leading `+` (matches every WAHA call
already in whatsapp.py and every docstring example, e.g. "2250767386180").
`default_region="CI"` lets a caller give a local Ivorian number without a
country code; a number with an explicit country code parses regardless of
this default.
"""




class HealthResponse(BaseModel):
    """What /health returns — and nothing else.

    Declaring the shape is what stops the endpoint leaking: returning the
    Settings object directly would send the database password.
    """
    status: str
    version: str
    env: str
    db_host: str
    db_port: int


T=TypeVar("T")

class Meta(BaseModel):
    """Facts *about* a response, alongside the data itself.

    Every field is optional because they do not all apply everywhere: a single
    instrument has no count, a reference list has no meaningful as_of.
    """
    count: int | None = None
    as_of: str | None = None 
    details : dict[str, Any] | None = None

class Envelope(BaseModel, Generic[T]):
    """The success shape: {"data": ..., "meta": {...}}.

    Generic, so `data` can be one instrument or a list of them while the
    envelope stays one class: Envelope[Instrument], Envelope[list[Instrument]].
    """
    data: T
    meta: Meta = Meta()


def envelope_(
            data, 
            count: int | None = None, 
            as_of: str | None = None,
            details: dict[str, Any] | None = None
        ) -> dict:
    """Builds a success response body in the {data, meta} contract.

    Every successful response has the same two top-level keys, so a client
    writes one function to unwrap them instead of one per endpoint. Failures
    use the other shape, {"error": {...}} — see app/core/errors.py.

    Args:
        data: The payload — one object, or a list of them.
        count (int | None): How many rows are in `data`. Meaningful on list
            endpoints, left None on single-object ones.
        as_of (str | None): How fresh the data is. Matters for prices, not for
            reference data like the instrument list.
        details (dict | None): Endpoint-specific extras.

    Returns:
        dict: {"data": ..., "meta": {"count": ..., "as_of": ..., "details": ...}}

    Examples:
        >>> envelope_(data=[{"symbol": "SNTS"}], count=1)
        {'data': [{'symbol': 'SNTS'}], 'meta': {'count': 1, 'as_of': None, 'details': None}}
    """
    return_envelope = {
        "data": data,
        "meta": 
            {"count": count,
            "as_of": as_of,
            "details": details ,
            }
   }

    return return_envelope

class ErrorBody(BaseModel):
    """The inside of a failure: code, message, status, optional details."""
    code: str 
    message : str
    status: int
    details: Any = None 

class ErrorEnvelope(BaseModel):
    """The failure shape: {"error": {...}}.

    One top-level key, so a client tests `"error" in body` once and knows,
    whatever endpoint it called.
    """
    error: ErrorBody




# 1. Define the strict validation function
def _validate_hard_password(v: str) -> str:
    # don't change the way it's import or go back in circular import 
    from app.core.errors import PasswordPolicyError

    # order matter!
    if len(v) < 12:
        raise PasswordPolicyError("The password must contain at least 12 characters.")
    if not re.search(r"[A-Z]", v):
        raise PasswordPolicyError("The password must contain at least one uppercase letter (A-Z).")
    if not re.search(r"[a-z]", v):
        raise PasswordPolicyError("The password must contain at least one lowercase letter (a-z).")
    if not re.search(r"[0-9]", v):
        raise PasswordPolicyError("The password must contain at least one digit (0-9).")
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', v):
        raise PasswordPolicyError("The password must contain at least one special character.")
    return v

# 2. Create a reusable type for your models
HardPassword = Annotated[str, AfterValidator(_validate_hard_password)]
