"""Instruments service — the data and the rules. Knows nothing about HTTP."""

INSTRUMENTS = [
    {"symbol": "SNTS", "name": "Sonatel", "type": "stock", "sector": "telecom"},
    {"symbol": "BOAB", "name": "Bank of Africa Bénin", "type": "stock", "sector": "finance"},
    {"symbol": "SGBC", "name": "Société Générale CI", "type": "stock", "sector": "finance"},
    {"symbol": "BRVM10", "name": "BRVM 10", "type": "index", "sector": None},
]


def list_instruments(
    type_: str | None = None,
    sector: str | None = None,
    limit: int = 20,
) -> list[dict]:
    rows = INSTRUMENTS
    if type_:
        rows = [r for r in rows if r["type"] == type_]
    if sector:
        rows = [r for r in rows if r["sector"] == sector]
    return rows[:limit]


def get_by_symbol(symbol: str) -> dict | None:
    for row in INSTRUMENTS:
        if row["symbol"] == symbol.upper():
            return row

            