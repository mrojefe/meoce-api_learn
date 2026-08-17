"""Instruments service — the data and the rules. Knows nothing about HTTP."""
from app.schemas  import  instruments


INSTRUMENTS = [
    {"symbol": "SNTS", "name": "Sonatel", "type": "stock", "sector": "telecom"},
    {"symbol": "BOAB", "name": "Bank of Africa Bénin", "type": "stock", "sector": "finance"},
    {"symbol": "SGBC", "name": "Société Générale CI", "type": "stock", "sector": "finance"},
    {"symbol": "BRVM10", "name": "BRVM 10", "type": "index", "sector": None},
    {"symbol": "SNTS", "name": "Sonatel", "type": "stock", "sector": "telecom","internal_note": "do not show"},
    {"symbol":"ORAC","name":"Orange Côte d’Ivoire","type":"stock","sector":"telecommunications"}
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

def create_instrument(symbol: str, name: str, type_: str,
                     sector: str | None = None) -> dict:
    new_instrument = {
                  "symbol":symbol , 
                  "name":name,
                  "type":type_,
                  "sector":sector
                  }
    for instrument in INSTRUMENTS:
        if instrument["symbol"] == new_instrument["symbol"]:
            raise ValueError("This instrument already exist")

           
    INSTRUMENTS.append(new_instrument)
    return   new_instrument
