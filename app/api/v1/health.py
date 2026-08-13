"""Liveness probe - see model 01 """

from fastapi import APIRouter
from app.core.config import API_VERSION

router = APIRouter(tags=["health"])

@router.get("/health")
def health():
    return {"status": "ok" ,"version": API_VERSION}