from datetime import datetime

from pydantic import BaseModel, Field


class UserProfile(BaseModel):
    """The caller's own profile, as GET /users/me returns it.

    Not `role`/`account_kind` — those decide what the caller may do, not
    something a profile screen shows back to them. `status`, `created_at`,
    `last_login` are read-only here: shown, never accepted in an update.
    """

    username: str
    email: str | None
    phone: str | None
    first_name: str | None
    last_name: str | None
    display_name: str | None
    bio: str | None
    avatar_url: str | None
    country: str | None
    profile_completed: bool | None
    last_login: datetime | None
    created_at: datetime
    status: str


class UserProfileUpdate(BaseModel):
    """The body accepted by PATCH /users/me. Every field is optional.

    Same partial-update shape as `WatchlistUpdate`/`PreferencesUpdate`: a
    field left out of the request stays untouched — `model_fields_set` in
    the route decides what actually gets written, not the value here.

    `email`/`phone` are deliberately absent: changing those needs a
    verification step this API doesn't have yet. `role`/`status`/
    `account_kind` are absent too — admin-only, not user-editable.

    `country`/`profile_completed` live on `user_profiles`, same as the rest
    of this schema's fields — but the route still splits them off before
    calling `update_profile`, and sends them to `update_identity_fields`
    instead, a separately whitelisted function. They're listed here anyway
    because this schema is what the client sends in one PATCH body; which
    service function ends up writing each field is an implementation detail
    the client doesn't need to know.
    """

    username: str | None = Field(default=None, min_length=3, max_length=32)
    first_name: str | None = None
    last_name: str | None = None
    display_name: str | None = None
    bio: str | None = None
    avatar_url: str | None = None
    country: str | None = Field(default=None, max_length=64)
    profile_completed: bool | None = None
