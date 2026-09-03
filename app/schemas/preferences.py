from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel


class Preferences(BaseModel):
    """One user's preferences, as this API returns them.

    `user_id` is NOT returned — same reasoning as `Watchlist`: the caller
    already knows who they are, and every field here would carry the same
    value, so it is used to filter and then dropped.

    All 15 columns, not just the 6 the real API's route exposes (see
    FINDINGS_FROM_THE_API_COURSE.md F-07): this API replaces the real one, so
    the frontend should be able to read/write the full set from here.
    """

    default_currency: str | None
    default_language: str | None
    default_timeframe: str | None
    default_chart_type: str | None
    default_watchlist_id: UUID | None
    default_template_id: UUID | None
    investor_experience: str | None
    investor_horizon: str | None
    investor_sectors: list[str] | None
    discovery_source: str | None
    notif_pref: str | None
    ui_state: dict[str, Any] | None
    timezone: str | None
    created_at: datetime
    updated_at: datetime


class PreferencesUpdate(BaseModel):
    """The body accepted by PATCH /preferences. Every field is optional.

    Same shape as `WatchlistUpdate`: a field left out of the request stays
    untouched in the database — `model_fields_set` in the route is what
    tells `update_preferences` which of these 13 were actually sent, not
    the value here (which Pydantic fills to `None` either way).
    """

    default_currency: str | None = None
    default_language: str | None = None
    default_timeframe: str | None = None
    default_chart_type: str | None = None
    default_watchlist_id: UUID | None = None
    default_template_id: UUID | None = None
    investor_experience: str | None = None
    investor_horizon: str | None = None
    investor_sectors: list[str] | None = None
    discovery_source: str | None = None
    notif_pref: str | None = None
    ui_state: dict[str, Any] | None = None
    timezone: str | None = None
