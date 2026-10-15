"""
Endpoints de salud diferenciados para las probes de Kubernetes.

La distincion importa: si /health/ready fallara por una caida temporal de la
base de datos y la liveness probe apuntara al mismo endpoint, Kubernetes
reiniciaria el pod en lugar de simplemente sacarlo del balanceo. Reiniciar no
arregla una base de datos caida, solo agrega un CrashLoopBackOff al problema.
"""
from fastapi import APIRouter, Response, status
from sqlalchemy import text

from src.models.database import engine

router = APIRouter(tags=["health"])


@router.get("/health/live")
def liveness():
    """Liveness: el proceso responde. No toca dependencias externas a proposito."""
    return {"status": "alive"}


@router.get("/health/ready")
def readiness(response: Response):
    """Readiness: ademas de vivir, puede atender trafico (la BD responde)."""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ready", "database": "up"}
    except Exception as exc:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not-ready", "database": "down", "detail": str(exc)}


@router.get("/health")
def health():
    """Alias de compatibilidad con la Practica 4."""
    return {"status": "ok"}
