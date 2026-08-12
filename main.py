"""MEOCE learn-API — entry point.

Rebuilt by hand from meoce-api/ as a learning exercise.
"""
VERSION = "0.1.0"

from fastapi import FastAPI

app = FastAPI(
    title= "Meoce Learn-API",
    description="A smaller Meoce,Built by hand.",
    version= VERSION,
)

@app.get("/api/v1/health")
def health():
    return {"status": "ok", "version": undefined_thing}