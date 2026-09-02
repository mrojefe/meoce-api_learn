from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, Field


class Watchlist(BaseModel):
    """One watchlist, as this API returns it.

    Deliberately not a copy of the table. Two decisions are visible here:

    * `id` is returned. The client needs it to build the next URL —
      `/watchlists/{id}/items`, `DELETE /watchlists/{id}`. A name cannot serve:
      two users may both have a list called "look", and a name can be renamed.
    * `user_id` is NOT returned. It is used to filter and then dropped: the
      caller already knows who they are, and every row would carry the same
      value. A response model is a decision about what to expose.
    """

    id: UUID
    name: Annotated[str ,Field(min_length=1, max_length=80)]
    description: Annotated[str | None,Field(description= "description of the watchlist")] = None
    is_public: Annotated[bool, Field(description="make it visible for everyone"+ 
                                    "only editeable by admin ")]=False


class WatchlistItemAdd(BaseModel):
    symbol: Annotated[str , Field(..., min_length=1, max_length=20)]