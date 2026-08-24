from typing import Annotated, Generic, TypeVar, Any
from pydantic import BaseModel, Field ,BeforeValidator





Symbol = Annotated[
    str,
    BeforeValidator(lambda v: v.strip().upper() if isinstance(v,str) else v),
    Field(min_length=2, max_length=12, pattern=r"^[A-Z0-9.]+$",
         description='BRVM ticker,uppercase - Snts == SNTS',
         examples=["SNTS"]) # Take the first element of AllowedSmbol   
] 


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
            details: dict[str, Any] = None
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