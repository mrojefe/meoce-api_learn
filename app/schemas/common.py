from typing import Annotated
from pydantic import BaseModel, Field ,BeforeValidator





Symbol = Annotated[
    str,
    BeforeValidator(lambda v: v.strip().upper() if isinstance(v,str) else v),
    Field(min_length=2, max_length=12, pattern=r"^[A-Z0-9.]+$",
         description='BRVM ticker,uppercase - Snts == SNTS')
]