"""Instruments service — the data and the rules. Knows nothing about HTTP."""

from app.core.errors import NotFoundError, ConflictError
from app.core.constant import INSTRUMENTS


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


def get_by_symbol(symbol: str) -> dict :
    for row in INSTRUMENTS:
        if row["symbol"] == symbol.upper():
            return row      
    raise  NotFoundError("this symbol doesn't exist")  


def get_summary_by_symbol(symbol:str)-> dict:
        for row in INSTRUMENTS:
            if row["symbol"] == symbol.upper():
                symbol=row.get('symbol')
                return {"summary":f"the market is close for {symbol}"}
        raise  NotFoundError("this symbol doesn't exist")            




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
            raise ConflictError("This instrument already exist")

           
    INSTRUMENTS.append(new_instrument)
    return   new_instrument
