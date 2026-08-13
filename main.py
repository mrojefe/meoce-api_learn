"""MEOCE learn-API — entry point.

Rebuilt by hand from meoce-api/ as a learning exercise.
"""

#----------------------------------------------------------------------------
VERSION = "0.1.0"
INSTRUMENTS = [
    {"symbol": "SNTS", "name": "Sonatel", "type": "stock", "sector": "telecom"},
    {"symbol": "BOAB", "name": "Bank of Africa Bénin", "type": "stock", "sector": "finance"},
    {"symbol": "SGBC", "name": "Société Générale CI", "type": "stock", "sector": "finance"},
    {"symbol": "BRVM10", "name": "BRVM 10", "type": "index", "sector": None},
]


#----------------------------------------------------------------------------



from fastapi import FastAPI
from fastapi import Query 

app = FastAPI(
    title= "Meoce Learn-API",
    description="A smaller Meoce,Built by hand.",
    version= VERSION,
)

@app.get("/api/v1/health")
def health():
    return {"status": "ok", "version": VERSION}


@app.get("/api/v1/instruments")
def lis_instruments(
    type: str | None = None,
    sector: str | None = None,
    limit: int = Query(default=2, ge=1, le=100, description="max rows returned"),  
):
    rows =  INSTRUMENTS

    if type is not None:
        rows = [r for r in rows if r["type"] == type]
    if sector is not None : 
        rows = [r for r in rows if rows if r["sector"] == sector]
    return {"data": rows[:limit] , "count": len(rows[:limit])}    




@app.get("/api/v1/instruments/{symbol}")
def get_instrument(symbol: str):
    for row in INSTRUMENTS:
        if row["symbol"] == symbol.upper():
            return {"data":row}


            
    return {"data": None}    