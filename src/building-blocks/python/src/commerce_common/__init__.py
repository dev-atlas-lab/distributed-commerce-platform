"""Shared cross-cutting foundations for Python services/workers (M0.3.1 Foundation)."""

from __future__ import annotations

import logging
import os
import uuid
from collections.abc import Mapping
from datetime import UTC, datetime

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from .error_codes import ErrorCode
from .exceptions import (
    ConflictException,
    DomainException,
    InfrastructureException,
    NotFoundException,
    ValidationException,
)
from .pagination import (
    CursorRequest,
    CursorResult,
    PagedResult,
    PageRequest,
    SortDirection,
)

logger = logging.getLogger(__name__)

CORRELATION_ID_HEADER = "X-Correlation-Id"
DEFAULT_INFRASTRUCTURE_DETAIL = "An infrastructure error occurred while processing the request."
DEFAULT_UNHANDLED_DETAIL = "An unexpected internal error occurred."


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


def _build_problem_details_response(
    request: Request,
    service_name: str,
    status_code: int,
    title: str,
    problem_type: str,
    detail: str,
    error_code: str,
) -> JSONResponse:
    correlation_id: str = getattr(request.state, "correlation_id", str(uuid.uuid4()))
    trace_id: str = getattr(request.state, "trace_id", correlation_id)
    return JSONResponse(
        status_code=status_code,
        media_type="application/problem+json",
        headers={CORRELATION_ID_HEADER: correlation_id},
        content={
            "type": problem_type,
            "title": title,
            "status": status_code,
            "detail": detail,
            "instance": str(request.url.path),
            "service": service_name,
            "errorCode": error_code,
            "correlationId": correlation_id,
            "traceId": trace_id,
            "timestamp": datetime.now(UTC).isoformat(),
        },
    )


def register_problem_details_handlers(app: FastAPI, service_name: str) -> None:
    """Registers RFC 9457 ProblemDetails exception handling (NFR-OBS-002)."""

    @app.exception_handler(ValidationException)
    async def handle_validation_exception(request: Request, exc: ValidationException) -> JSONResponse:
        logger.warning("Validation error [%s]: %s", exc.error_code, exc.message)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=400,
            title="Bad Request",
            problem_type="https://problems.commerce.dev-atlas.lab/validation-error",
            detail=exc.message,
            error_code=exc.error_code,
        )

    @app.exception_handler(NotFoundException)
    async def handle_not_found_exception(request: Request, exc: NotFoundException) -> JSONResponse:
        logger.warning("Resource not found [%s]: %s", exc.error_code, exc.message)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=404,
            title="Not Found",
            problem_type="https://problems.commerce.dev-atlas.lab/not-found",
            detail=exc.message,
            error_code=exc.error_code,
        )

    @app.exception_handler(ConflictException)
    async def handle_conflict_exception(request: Request, exc: ConflictException) -> JSONResponse:
        logger.warning("State conflict [%s]: %s", exc.error_code, exc.message)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=409,
            title="Conflict",
            problem_type="https://problems.commerce.dev-atlas.lab/conflict",
            detail=exc.message,
            error_code=exc.error_code,
        )

    @app.exception_handler(DomainException)
    async def handle_domain_exception(request: Request, exc: DomainException) -> JSONResponse:
        logger.warning("Domain rule violation [%s]: %s", exc.error_code, exc.message)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=409,
            title="Domain Rule Violation",
            problem_type="https://problems.commerce.dev-atlas.lab/domain-violation",
            detail=exc.message,
            error_code=exc.error_code,
        )

    @app.exception_handler(InfrastructureException)
    async def handle_infrastructure_exception(
        request: Request, exc: InfrastructureException
    ) -> JSONResponse:
        logger.error("Infrastructure technical failure [%s]: %s", exc.error_code, exc.message)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=500,
            title="Internal Technical Failure",
            problem_type="https://problems.commerce.dev-atlas.lab/infrastructure-error",
            detail=DEFAULT_INFRASTRUCTURE_DETAIL,
            error_code=exc.error_code,
        )

    @app.exception_handler(ValueError)
    async def handle_value_error(request: Request, exc: ValueError) -> JSONResponse:
        logger.warning("Invalid argument: %s", exc)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=400,
            title="Bad Request",
            problem_type="https://problems.commerce.dev-atlas.lab/bad-request",
            detail=str(exc),
            error_code="INVALID_ARGUMENT",
        )

    @app.exception_handler(Exception)
    async def handle_generic_exception(request: Request, exc: Exception) -> JSONResponse:
        logger.error("Unhandled server exception: %s", exc)
        return _build_problem_details_response(
            request=request,
            service_name=service_name,
            status_code=500,
            title="Internal Server Error",
            problem_type="https://problems.commerce.dev-atlas.lab/internal-error",
            detail=DEFAULT_UNHANDLED_DETAIL,
            error_code="INTERNAL_SERVER_ERROR",
        )


__all__ = [
    "CORRELATION_ID_HEADER",
    "ConflictException",
    "CorrelationIdMiddleware",
    "CursorRequest",
    "CursorResult",
    "DomainException",
    "ErrorCode",
    "InfrastructureException",
    "NotFoundException",
    "PageRequest",
    "PagedResult",
    "SortDirection",
    "ValidationException",
    "register_problem_details_handlers",
    "verify_fault_injection_guard",
]
