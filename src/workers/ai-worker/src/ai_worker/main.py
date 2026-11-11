"""Entry point for the AI Shopping & Operations Worker (M0.3 Foundation)."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from commerce_common import (
    CorrelationIdMiddleware,
    register_problem_details_handlers,
    verify_fault_injection_guard,
)
from fastapi import FastAPI


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    verify_fault_injection_guard()
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="Commerce AI Worker API",
        version="0.1.0",
        description="Read-only/advisory AI Shopping & Ops Assistant Foundation (M0.3)",
        lifespan=lifespan,
    )
    app.add_middleware(CorrelationIdMiddleware)
    register_problem_details_handlers(app, service_name="ai-worker")

    @app.get("/health/live", tags=["health"])
    async def liveness_probe() -> dict[str, str]:
        return {"status": "UP", "service": "ai-worker"}

    @app.get("/health/ready", tags=["health"])
    async def readiness_probe() -> dict[str, str]:
        return {"status": "UP", "service": "ai-worker"}

    return app


app = create_app()
