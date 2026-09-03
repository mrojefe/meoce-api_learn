from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.common import Symbol


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
    is_public: Annotated[bool, Field(description="make it visible for everyone"
                                    "only editeable by admin ")] = False


class WatchlistCreate(BaseModel):
    """The body accepted by POST /watchlists.

    Three fields, and the two that are missing are the point: no `id`, because
    the database generates it, and no `user_id`, because the owner comes from
    the token. There is no way to express "create this in someone else's
    account", and no way to choose your own id.
    """

    name: Annotated[str, Field(min_length=1, max_length=80,
                               description="Shown in the sidebar. Not unique — "
                                           "two of your lists may share a name.")]
    description: Annotated[str | None, Field(
        description="Optional note about what the list is for.")] = None
    is_public: Annotated[bool, Field(
        description="Whether other users may see it.")] = False


class WatchlistUpdate(BaseModel):
    """The body accepted by PATCH /watchlists/{id}. Every field is optional.

    A `None` here does NOT mean "clear this field" — it means "not sent,
    Pydantic filled it in." The service never trusts these values directly;
    it checks `model_fields_set` first to see which keys were actually in
    the request body, and only touches those columns.
    """

    name: Annotated[str | None, Field(
        default=None, min_length=1, max_length=80,
        description="New name, if changing it.")]
    description: Annotated[str | None, Field(
        default=None, description="New description, if changing it.")]
    is_public: Annotated[bool | None, Field(
        default=None, description="New visibility, if changing it.")]


class WatchlistItemAdd(BaseModel):
    """The body accepted by POST /watchlists/{id}/items.

    `Symbol` — the same type instruments already use — so "snts" and "SNTS"
    in the body reach the service as the same value, exactly like the
    `symbol` path parameter on the DELETE route.
    """

    symbol: Symbol


class WatchlistItem(BaseModel):
    """One instrument inside a watchlist, as GET /watchlists/{id}/items
    returns it.

    Not a copy of `watchlist_items` either: `sector_name` is joined in from
    `instruments`/`sectors` because the caller wants to show a sector, not
    look one up separately. `watchlist_id`/`instrument_id` are not
    returned — the caller already knows which list they asked for, and
    `symbol` is what identifies the instrument everywhere else in this API.
    """

    symbol: str
    name: str
    sector_name: str | None
    sort_order: int | None
    added_at: datetime
    alert_enabled: bool
    target_price: float | None
    notes: str | None
