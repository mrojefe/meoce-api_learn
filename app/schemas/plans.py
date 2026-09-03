"""Subscription plans — the declared shape of what a plan grants.

`subscription_plans.features` is a JSONB blob: whatever was written into it, in
whatever shape. This module turns that blob into a model, which buys three
things a raw dict does not:

* **a typo becomes an error.** `extra="forbid"` means `max_watchlist` (missing
  the s) is refused when the plan is read, instead of returning None from
  `.get()` — and None is our convention for *unlimited*. Without this, one
  missing letter silently removes a limit.
* **types are checked.** A limit that arrives as `"2"` rather than `2` is caught
  here rather than three layers down, where it would compare wrong.
* **the defaults are stated once**, so a plan that omits a key does not leave
  each caller guessing.

What is deliberately NOT here: the values themselves. Those live in the
database, because a price or a limit changes for business reasons, at business
speed, and must never require a deploy. This file describes the *shape* of a
plan; `subscription_plans` holds *the* plans.
"""

from typing import Annotated

from pydantic import BaseModel, Field


class PlanFeatures(BaseModel):
    """Everything a plan grants, parsed from `subscription_plans.features`.

    Two kinds of field, and the difference matters when reading them:

    * **switches** — a bool. Default `False`: a feature nobody granted is not
      granted. Silence denies.
    * **limits** — an int, or `None` meaning unlimited. Default `None`.

    Note the asymmetry, because it is a trap: for a switch, "unspecified" means
    *no*; for a limit, it means *unlimited*. The same silence is restrictive in
    one case and permissive in the other. That is exactly how `multi_layout`,
    defined only on the free plan, ended up denied on the paid ones — and why
    every plan should state every key rather than relying on a default.

    Every active plan now states every key explicitly, enforced by
    `tests/test_reference_data.py`. The defaults above are a safety net for a
    plan created later and left incomplete, not something to rely on.
    """

    model_config = {"extra": "forbid"}

    # ── switches: a bool. Silence DENIES. ────────────────────────────────────
    news_feed: Annotated[bool, Field(
        description="Read the news feed at all. Every plan grants it today, so "
                    "nothing has ever depended on it.",
        examples=[True],
    )]

    realtime_candle: Annotated[bool, Field(
        description="Receive live candle updates rather than delayed ones. "
                    "Decides whether the server streams, so it belongs to the API.",
        examples=[True],
    )] 

    pro_chart_types: Annotated[bool, Field(
        description="Chart types beyond the free set — Heikin Ashi, Renko and "
                    "the rest.",
        examples=[False],
    )] 

    custom_timeframes: Annotated[bool, Field(
        description="Create your own timeframes, e.g. 12D. Aggregated "
                    "server-side, so the API decides.",
        examples=[False],
    )] 

    intraday_granular_timeframes: Annotated[bool, Field(
        description="Fine intraday resolution: 1mn and 30mn. The only feature "
                    "already gated by a dependency on the route.",
        examples=[False],
    )] 

    insights_ai_premium: Annotated[bool, Field(
        description="AI-generated insights. Each call costs money per request, "
                    "which is why it must be checked before the call is made.",
        examples=[False],
    )] 

    # ── limits: an int, or None meaning unlimited. Silence PERMITS. ──────────
    max_watchlists: Annotated[int | None, Field(
        ge=0,
        description="How many watchlists may exist. Rows in our database.",
        examples=[2],
    )] 

    max_real_portfolios: Annotated[int | None, Field(
        ge=0,
        description="Portfolios holding real positions. Note the live data has "
                    "free=2 and plus=1 — a paying user below a free one.",
        examples=[2],
    )] 

    max_virtual_portfolios: Annotated[int | None, Field(
        ge=0,
        description="Paper-trading portfolios.",
        examples=[2],
    )] 

    max_news_bookmarks: Annotated[int | None, Field(
        ge=0,
        description="Saved articles. Rows in our database.",
        examples=[5],
    )] 

    max_flags: Annotated[int | None, Field(
        ge=0,
        description="Coloured flags on instruments, stored in "
                    "user_instrument_flags and written through PUT /flags/{symbol}.",
        examples=[1],
    )] 

    max_alerts_active: Annotated[int | None, Field(
        ge=0,
        description="Alerts running at once. They execute on our server, so "
                    "each one costs us continuously.",
        examples=[2],
    )] 

    max_alerts_month: Annotated[int | None, Field(
        ge=0,
        description="Alerts that may fire within a calendar month.",
        examples=[10],
    )] 

    max_alerts_email_active: Annotated[int | None, Field(
        ge=0,
        description="Active email alerts. We pay to send.",
        examples=[5],
    )] 

    max_alerts_whatsapp_active: Annotated[int | None, Field(
        ge=0,
        description="Active WhatsApp alerts. Billed per message — the most "
                    "expensive limit to leave unenforced.",
        examples=[3],
    )] 

    max_chart_panes: Annotated[int | None, Field(
        ge=0,
        description="Chart panels on screen. The arrangement is the browser's "
                    "business, but each pane costs one history fetch, so what "
                    "the API owes here is a limit on data volume, not on panes.",
        examples=[1],
    )] 

    max_indicators_on_chart: Annotated[int | None, Field(
        ge=0,
        description="Indicators per chart. Computed in the browser over data "
                    "already sent, so genuinely the frontend's to enforce.",
        examples=[2],
    )] 

    max_custom_timeframes: Annotated[int | None, Field(
        ge=0,
        description="How many custom timeframes may be saved.",
        examples=[0],
    )] 

    max_screener_saves: Annotated[int | None, Field(
        ge=0,
        description="Saved screener filters.",
        examples=[2],
    )] 

    history_years_max: Annotated[int | None, Field(
        ge=0,
        description="How far back daily history may be requested. Decides what "
                    "data leaves our server — the most valuable limit we have.",
        examples=[3],
    )] 

    live_history_days: Annotated[int | None, Field(
        ge=0,
        description="Days of intraday history reachable.",
        examples=[5],
    )]
