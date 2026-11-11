"""Tests for RFC 9457 ProblemDetails handlers and exception taxonomy."""

from __future__ import annotations

import pytest
from commerce_common import (
    CORRELATION_ID_HEADER,
    ConflictException,
    DomainException,
    ErrorCode,
    InfrastructureException,
    NotFoundException,
    ValidationException,
)
from fastapi import FastAPI
from fastapi.testclient import TestClient


def create_test_app() -> FastAPI:
    from commerce_common import CorrelationIdMiddleware, register_problem_details_handlers

    test_app = FastAPI()
    test_app.add_middleware(CorrelationIdMiddleware)
    register_problem_details_handlers(test_app, service_name="ai-worker-test")

    @test_app.get("/test/validation")
    async def route_validation() -> dict[str, str]:
        raise ValidationException("INVALID_QUERY", "Search query cannot be blank")

    @test_app.get("/test/not-found")
    async def route_not_found() -> dict[str, str]:
        raise NotFoundException("AGENT_SESSION_NOT_FOUND", "Session session-123 not found")

    @test_app.get("/test/conflict")
    async def route_conflict() -> dict[str, str]:
        raise ConflictException("ACTIVE_SESSION_CONFLICT", "A live session already exists")

    @test_app.get("/test/domain")
    async def route_domain() -> dict[str, str]:
        raise DomainException("INSUFFICIENT_CONTEXT_BUDGET", "Token budget exceeded for session")

    @test_app.get("/test/infrastructure")
    async def route_infra() -> dict[str, str]:
        raise InfrastructureException(
            "PGVECTOR_CONNECTION_REFUSED",
            "FATAL: password authentication failed for user secret_user"
        )

    @test_app.get("/test/value-error")
    async def route_value_error() -> dict[str, str]:
        raise ValueError("Invalid parameter value")

    @test_app.get("/test/unhandled")
    async def route_unhandled() -> dict[str, str]:
        raise RuntimeError("Unexpected failure with internal details")

    return test_app


def test_exception_taxonomy_properties() -> None:
    d_ex = DomainException("ERR_CODE_1", "domain msg")
    assert d_ex.error_code == "ERR_CODE_1"
    assert d_ex.message == "domain msg"
    assert str(d_ex) == "domain msg"

    typed_ex = DomainException(ErrorCode.PRODUCT_ARCHIVED, "domain msg")
    assert typed_ex.error_code == "PRODUCT_ARCHIVED"

    with pytest.raises(ValueError, match="error_code must not be empty"):
        DomainException("", "msg")


def test_validation_exception_maps_to_400_problem_details() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/validation", headers={CORRELATION_ID_HEADER: "py-corr-101"})
    assert resp.status_code == 400
    assert resp.headers["content-type"] == "application/problem+json"
    assert resp.headers[CORRELATION_ID_HEADER] == "py-corr-101"

    data = resp.json()
    assert data["status"] == 400
    assert data["title"] == "Bad Request"
    assert data["errorCode"] == "INVALID_QUERY"
    assert data["detail"] == "Search query cannot be blank"
    assert data["correlationId"] == "py-corr-101"
    assert data["service"] == "ai-worker-test"
    assert "timestamp" in data


def test_not_found_exception_maps_to_404_problem_details() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/not-found")
    assert resp.status_code == 404
    data = resp.json()
    assert data["status"] == 404
    assert data["title"] == "Not Found"
    assert data["errorCode"] == "AGENT_SESSION_NOT_FOUND"
    assert data["detail"] == "Session session-123 not found"


def test_conflict_exception_maps_to_409_problem_details() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/conflict")
    assert resp.status_code == 409
    data = resp.json()
    assert data["status"] == 409
    assert data["title"] == "Conflict"
    assert data["errorCode"] == "ACTIVE_SESSION_CONFLICT"


def test_domain_exception_maps_to_409_problem_details() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/domain")
    assert resp.status_code == 409
    data = resp.json()
    assert data["status"] == 409
    assert data["title"] == "Domain Rule Violation"
    assert data["errorCode"] == "INSUFFICIENT_CONTEXT_BUDGET"


def test_infrastructure_exception_maps_to_500_and_sanitizes_detail() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/infrastructure")
    assert resp.status_code == 500
    data = resp.json()
    assert data["status"] == 500
    assert data["title"] == "Internal Technical Failure"
    assert data["errorCode"] == "PGVECTOR_CONNECTION_REFUSED"
    assert data["detail"] == "An infrastructure error occurred while processing the request."
    assert "secret_user" not in data["detail"]


def test_value_error_maps_to_400_problem_details() -> None:
    client = TestClient(create_test_app())
    resp = client.get("/test/value-error")
    assert resp.status_code == 400
    data = resp.json()
    assert data["status"] == 400
    assert data["errorCode"] == "INVALID_ARGUMENT"


def test_unhandled_exception_maps_to_500_problem_details() -> None:
    client = TestClient(create_test_app(), raise_server_exceptions=False)
    resp = client.get("/test/unhandled")
    assert resp.status_code == 500
    data = resp.json()
    assert data["status"] == 500
    assert data["title"] == "Internal Server Error"
    assert data["errorCode"] == "INTERNAL_SERVER_ERROR"
    assert data["detail"] == "An unexpected internal error occurred."
    assert "internal details" not in data["detail"]
