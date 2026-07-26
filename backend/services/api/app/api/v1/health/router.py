"""
Dilix — Health Check Endpoints
"""
import time
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.database import get_db
from app.core.redis import get_redis

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("/", summary="بررسی سلامت کلی")
async def health_check(
    db: AsyncSession = Depends(get_db),
    redis=Depends(get_redis),
):
    checks = {}
    overall = "healthy"

    # Database
    try:
        start = time.time()
        await db.execute(text("SELECT 1"))
        checks["database"] = {"status": "healthy", "latency_ms": round((time.time() - start) * 1000, 2)}
    except Exception as e:
        checks["database"] = {"status": "unhealthy", "error": str(e)}
        overall = "unhealthy"

    # Redis
    try:
        start = time.time()
        await redis.ping()
        checks["redis"] = {"status": "healthy", "latency_ms": round((time.time() - start) * 1000, 2)}
    except Exception as e:
        checks["redis"] = {"status": "unhealthy", "error": str(e)}
        overall = "degraded" if overall == "healthy" else overall

    return {
        "status": overall,
        "service": "dilix-api",
        "version": "1.0.0",
        "checks": checks,
    }


@router.get("/live", summary="Liveness probe (Kubernetes)")
async def liveness():
    return {"status": "alive"}


@router.get("/ready", summary="Readiness probe (Kubernetes)")
async def readiness(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception:
        from fastapi import Response
        return Response(content='{"status":"not_ready"}', status_code=503)
