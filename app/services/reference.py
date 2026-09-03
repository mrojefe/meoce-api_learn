"""Reference data service — public, read-only lookups for frontend dropdowns.

Different job from `app/core/reference.py`: that module builds the closed-set
enums this API *validates against*, once, at import. This module answers a
request — "what currencies exist right now" — so it uses `query()` (the pool,
opened by the lifespan) rather than `direct_query()` (its own connection,
for code that runs before the pool exists).
"""

from app.core.db.database import query


def list_currencies() -> tuple[list[dict], list[dict]]:
    """Every currency, and the rate-conversion presets shown alongside them.

    Two unrelated tables, both small and both needed by the same screen (a
    currency picker with quick preset multipliers) — the real API bundles
    them in one response for that reason, and this mirrors it.

    Returns:
        tuple[list[dict], list[dict]]: (currencies, presets), each ordered
            by its own natural order — currencies by code, presets by
            `display_order`.

    Examples:
        >>> currencies, presets = list_currencies()
        >>> currencies[0]
        {'code': 'EUR', 'name': 'Euro', 'symbol': '€', ...}
        >>> presets[0]
        {'code': 'conservative', 'rate_multiplier': 0.97, 'display_order': 1}
    """
    sql_currencies = "SELECT * FROM currencies ORDER BY code"
    currencies = query(sql_currencies)

    sql_presets = "SELECT * FROM currency_rate_presets ORDER BY display_order"
    presets = query(sql_presets)

    return currencies, presets


def list_sectors() -> tuple[list[dict], list[dict]]:
    """Every sector, and every subsector, each ordered by name.

    Same bundling reasoning as `list_currencies`: one screen (a sector
    filter) wants both. Unlike currencies/presets though, these two ARE
    related — `subsectors.sector_id` is a real foreign key — the caller is
    expected to group subsectors under their sector itself, this function
    just hands back both flat lists.

    Returns:
        tuple[list[dict], list[dict]]: (sectors, subsectors).

    Examples:
        >>> sectors, subsectors = list_sectors()
        >>> sectors[0]
        {'id': 1, 'name': 'AGRICULTURE'}
    """
    sql_sectors = "SELECT id, name FROM sectors ORDER BY name"
    sectors = query(sql_sectors)

    sql_subsectors = "SELECT id, sector_id, name FROM subsectors ORDER BY name"
    subsectors = query(sql_subsectors)

    return sectors, subsectors


def list_countries() -> tuple[list[dict], int]:
    """Every country, ordered by name.

    A single table, unlike currencies and sectors — so this returns a plain
    list, not a bundle of two.

    Returns:
        tuple[list[dict], int]: The rows, and how many there are.

    Examples:
        >>> countries, count = list_countries()
        >>> countries[0]
        {'code': 'BJ', 'name': 'Bénin', 'region': 'West Africa', ...}
    """
    sql_countries = "SELECT * FROM countries ORDER BY name"
    countries = query(sql_countries)

    return countries, len(countries)


def list_exchanges() -> tuple[list[dict], int]:
    """Every exchange, ordered by name.

    Args: none.

    Returns:
        tuple[list[dict], int]: The rows, and how many there are.

    Examples:
        >>> exchanges, count = list_exchanges()
        >>> exchanges[0]
        {'id': 1, 'code': 'BRVM', 'name': '...', 'timezone': 'Africa/Abidjan', ...}
    """
    sql_exchanges = "SELECT * FROM exchanges ORDER BY name"
    exchanges = query(sql_exchanges)

    return exchanges, len(exchanges)
