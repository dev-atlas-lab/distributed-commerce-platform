"""Shared cross-cutting foundations for Python services/workers (M0.3.1 Foundation)."""

from __future__ import annotations

import os
import uuid
from collections.abc import Mapping
from datetime import UTC, datetime

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

CORRELATION_ID_HEADER = "X-Correlation-Id"


def verify_fault_injection_guard(env: Mapping[str, str] | None = None) -> None:
    """Enforce CH-07 / NFR-SEC-004: Fail-closed startup guard in production."""
    source = env if env is not None else os.environ
    environment = source.get("ENVIRONMENT", "development").strip().lower()
    production_lock = source.get("PRODUCTION_LOCK", "false").strip().lower() == "true"
    fault_enabled = source.get("FAULT_INJECTION_ENABLED", "false").strip().lower() == "true"

    is_production = production_lock or environment in {"prod", "production"}
    if is_production and fault_enabled:
        raise RuntimeError(
            "SECURITY_VIOLATION: FAULT_INJECTION_ENABLED=true is forbidden in production environment (CH-07)."
        )


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """Propagates or generates X-Correlation-Id header on every HTTP request (NFR-OBS-001)."""

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        correlation_id = request.headers.get(CORRELATION_ID_HEADER) or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        response = await call_next(request)
        response.headers[CORRELATION_ID_HEADER] = correlation_id
        return response


def register_problem_details_handlers(app: FastAPI, service_name: str) -> None:
    """Registers RFC 9457 ProblemDetails exception handling (NFR-OBS-002)."""

    @app.exception_handler(ValueError)
    async def handle_value_error(request: Request, exc: ValueError) -> JSONResponse:
        correlation_id = getattr(request.state, "correlation_id", str(uuid.uuid4()))
        return JSONResponse(
            status_code=400,
            media_type="application/problem+json",
            headers={CORRELATION_ID_HEADER: correlation_id},
            content={
                "type": "https://problems.commerce.dev-atlas.lab/bad-request",
                "title": "Bad Request",
                "status": 400,
                "detail": str(exc),
                "instance": str(request.url.path),
                "service": service_name,
                "correlationId": correlation_id,
                "timestamp": datetime.now(UTC).isoformat(),
            },
        )
