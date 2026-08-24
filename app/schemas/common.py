from typing import Annotated, Generic, TypeVar, Any
from pydantic import BaseModel, Field ,BeforeValidator





Symbol = Annotated[
    str,
    BeforeValidator(lambda v: v.strip().upper() if isinstance(v,str) else v),
    Field(min_length=2, max_length=12, pattern=r"^[A-Z0-9.]+$",
         description='BRVM ticker,uppercase - Snts == SNTS',
         examples="SNTS") # Take the first element of AllowedSmbol   
]


class HealthResponse(BaseModel):
    status: str
    version: str
    env: str
    db_host: str
    db_port: int


T=TypeVar("T")


class Meta(BaseModel):
    count: int | None = None
    as_of: str | None = None 


class ErrorBody(BaseModel):
    code: str 
    message : str
    status: int
    details: Any = None 



class Envelope(BaseModel, Generic[T]):
    data: T
    meta: Meta = Meta()



class ErrorEnvelope(BaseModel):
    error: ErrorBody