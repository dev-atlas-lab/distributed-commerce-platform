"""Unit and smoke tests for AI Worker foundation and CH-07 startup guard."""

from __future__ import annotations

import pytest
from commerce_common import CORRELATION_ID_HEADER, verify_fault_injection_guard
from fastapi.testclient import TestClient

from ai_worker.main import create_app


def test_liveness_and_readiness_probes_propagate_correlation_id() -> None:
    app = create_app()
    with TestClient(app) as client:
        live_resp = client.get(
            "/health/live", headers={CORRELATION_ID_HEADER: "ai-corr-001"}
        )
        assert live_resp.status_code == 200
        assert live_resp.json() == {"status": "UP", "service": "ai-worker"}
        assert live_resp.headers[CORRELATION_ID_HEADER] == "ai-corr-001"

        ready_resp = client.get("/health/ready")
        assert ready_resp.status_code == 200
        assert ready_resp.json()["status"] == "UP"
        assert CORRELATION_ID_HEADER in ready_resp.headers


def test_fault_injection_guard_fails_closed_in_production() -> None:
    with pytest.raises(RuntimeError, match="SECURITY_VIOLATION"):
        verify_fault_injection_guard(
            {"ENVIRONMENT": "production", "FAULT_INJECTION_ENABLED": "true"}
        )


def test_fault_injection_guard_allows_safe_configurations() -> None:
    verify_fault_injection_guard(
        {"ENVIRONMENT": "production", "FAULT_INJECTION_ENABLED": "false"}
    )
    verify_fault_injection_guard(
        {"ENVIRONMENT": "chaos", "FAULT_INJECTION_ENABLED": "true"}
    )
