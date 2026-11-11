# Non-Functional Requirements (`NON_FUNCTIONAL_REQUIREMENTS.md`)

**Milestone:** `M0.3` — Architecture Freeze and Source Foundation
**Status:** `DESIGN_ACCEPTED`
**Date:** 2026-04-11

This document specifies the non-functional requirements (Security, Reliability, Performance, Observability, Operations, and Governance) for `distributed-commerce-platform`. Every requirement links to its governing decision (`Q` / `CH` / `HD`) and verification method.

> **Verification Honesty Rule:** Performance SLOs and chaos survival budgets in this document are **benchmark objectives and engineering targets (`NEEDS_EVIDENCE`)**, not verified claims, until proven by load tests (`M10`) and chaos tests (`M11`).

---

## 1. Security Requirements (`NFR-SEC`)

| ID | Category | Requirement | Verification Method | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-SEC-001`** | Authentication & Token Type Separation | All services MUST validate JWT access tokens via standard OIDC discovery (`/.well-known/openid-configuration`) and JWKS signature verification. Services MUST reject OIDC ID tokens (`typ != at+jwt` or missing access token claims) on API endpoints with `401 Unauthorized`. | Security Integration Test (`tests/security/`) | `Q5`, `CH-05` (`ADR-0006`) |
| **`NFR-SEC-002`** | Audience & Principal Type Enforcement | Every resource server MUST validate that its specific audience identifier is present in the JWT `aud` claim and enforce `principal_type` separation (`CUSTOMER` vs `STAFF` vs `SERVICE`). Customer tokens MUST fail with `403 Forbidden` on `/api/v1/admin/**` and `/internal/**` endpoints even if forged role strings are present. | Security Integration Test (`tests/security/`) | `CH-05` (`ADR-0006`) |
| **`NFR-SEC-003`** | Least-Privilege Database Access (`Promotion`) | The Promotion application runtime role (`promotion_app_role`) MUST have `INSERT`, `UPDATE`, and `DELETE` privileges revoked on `flash_sale_campaigns`, `flash_sale_claims`, `flash_sale_items`, `outbox_messages`, and `idempotency_records`. All writes MUST occur through `SECURITY DEFINER` stored procedures (`fn_mp01`–`fn_mp08`) owned by a non-login, non-superuser role (`promotion_proc_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE`) with `SET search_path = pg_catalog, public`. | PostgreSQL Role & Privilege Integration Test (`tests/security/`) | `CH-01`, `HD-03` (`ADR-0005`) |
| **`NFR-SEC-004`** | Chaos Fault Injection Containment | Fault injection middleware MUST be disabled by default, restricted to non-production profiles, and fail-closed (aborting process startup immediately) if `ENVIRONMENT=production` (or `ASPNETCORE_ENVIRONMENT=Production` / `SPRING_PROFILES_ACTIVE=prod`) is combined with `FAULT_INJECTION_ENABLED=true`. Every injected fault MUST emit a structured audit log entry (`event_type = "chaos.fault_injected"`). | Startup Guard Unit Test + Security Test | `CH-07` (`ADR-0008`) |
| **`NFR-SEC-005`** | Secret & Webhook Hygiene | Zero secrets, private keys, or API tokens may be committed to Git. Payment provider webhooks MUST verify cryptographic HMAC signatures (`Stripe-Signature` / provider equivalent) and timestamp tolerance (`<= 300s`) before parsing payloads. | CI Secret Scan + Payment Webhook Unit Test | `CH-02` (`ADR-0004`) |

---

## 2. Reliability & Resilience Requirements (`NFR-REL`)

| ID | Category | Requirement | Verification Method | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-REL-001`** | Deadlock Freedom on Flash Sale Hot Path | Under concurrent contention across all eight Promotion mutation paths (`MP-01` through `MP-08`), PostgreSQL deadlocks (`SQLSTATE 40P01`) MUST be `0` due to strict canonical lock ordering (`flash_sale_campaigns -> flash_sale_claims -> flash_sale_items -> outbox_messages -> idempotency_records`) and explicit sorted multi-row locking (`ORDER BY id ASC FOR UPDATE`). | Concurrency Stress Test (`tests/integration/` & `tests/performance/`) | `CH-01`, `HD-01`, `HD-02`, `HD-03` (`ADR-0005`) |
| **`NFR-REL-002`** | Crash-Consistent Claim & Outbox Recovery | Pod crashes (`SIGKILL`), network partitions, or Redis restarts during an active Flash Sale campaign MUST NOT result in negative stock (`remaining_stock < 0`), orphaned unreleased claims past expiry + reconciliation window, or lost domain events. | Chaos Engineering Test (`M11`) | `CH-01`, `CH-04` (`ADR-0003`, `ADR-0005`) |
| **`NFR-REL-003`** | Bounded Downstream Timeout & Circuit Breaking | Synchronous inter-service calls and external provider calls MUST enforce explicit per-call timeouts (`<= 3000ms`), bounded retries with exponential backoff + jitter (only on idempotent operations), and circuit breaking to prevent cascading thread-pool exhaustion. | Resilience Integration Test | `CH-03` (`ADR-0002`, `ADR-0010`) |
| **`NFR-REL-004`** | Poison Message Isolation (DLQ) | Kafka consumers MUST isolate non-transient deserialization or schema validation failures into a Dead-Letter Queue (`<topic>.dlq`) after bounded retries without blocking healthy partitions, while transient version-gap events (`incoming.version > last_applied_version + 1`) are deferred/retried without data loss. | Messaging Integration Test | `CH-04` (`ADR-0003`) |

---

## 3. Performance & Scalability Targets (`NFR-PERF`) — `NEEDS_EVIDENCE`

> **Note:** All numeric targets below are **engineering benchmark objectives (`NEEDS_EVIDENCE`)** to be empirically measured and tuned on the target hardware topology during `M10`.

| ID | Category | Target Metric (`NEEDS_EVIDENCE`) | Measurement Conditions | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-PERF-001`** | Catalog & FTS Read Latency | `p95 <= 75ms`, `p99 <= 150ms` at `500 RPS` | 100k SKUs in PostgreSQL 17 with GIN `search_vector` index and Redis cache warm. | `Q6`, `CH-06` (`ADR-0007`) |
| **`NFR-PERF-002`** | Hybrid Semantic Search Latency (`pgvector`) | `p95 <= 180ms`, `p99 <= 300ms` at `100 RPS` | 100k product embeddings (`1536` dims, HNSW index `m=16, ef_construction=64`, `ef_search=40`) on 4-vCPU / 8-GiB PostgreSQL node. | `CH-06` (`ADR-0007`) |
| **`NFR-PERF-003`** | Flash Sale Claim Throughput & Latency | `p95 <= 120ms`, `p99 <= 250ms` at `1,000 concurrent virtual users` with `0` oversell (`remaining_stock >= 0`) | Active Flash Sale campaign with Redis Lua gate + PostgreSQL `fn_mp01_claim_campaign_stock`. | `CH-01` (`ADR-0005`) |
| **`NFR-PERF-004`** | Standard Order Checkout Latency | `p95 <= 250ms`, `p99 <= 500ms` at `200 RPS` | Synchronous Order creation + Outbox write (`POST /api/v1/orders`). | `CH-02`, `CH-03` (`ADR-0003`, `ADR-0004`) |

---

## 4. Observability Requirements (`NFR-OBS`)

| ID | Category | Requirement | Verification Method | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-OBS-001`** | Distributed Tracing & Correlation Propagation | Every HTTP gateway, microservice, gRPC endpoint, and Kafka producer/consumer MUST propagate W3C `traceparent`, `tracestate`, and `X-Correlation-Id` headers, and include `trace_id`, `span_id`, `correlation_id`, and `service_name` in structured JSON logs. | Observability Integration Test & Scaffold Unit Test | `ADR-0009` |
| **`NFR-OBS-002`** | RFC 9457 ProblemDetails Error Contract | Every HTTP API across Java (Spring Boot), .NET (`ASP.NET Core`), and Python (`FastAPI`) MUST return standardized `application/problem+json` (RFC 9457 `ProblemDetails`) responses for `4xx` and `5xx` errors, including `type`, `title`, `status`, `detail`, `instance`, and `correlationId` extension field. | API Contract & Unit Tests | `ADR-0010` |

---

## 5. Operational & Infrastructure Requirements (`NFR-OPS`)

| ID | Category | Requirement | Verification Method | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-OPS-001`** | Health & Readiness Probes | Every deployable service and worker MUST expose distinct liveness (`/health/live` or `/actuator/health/liveness`) and readiness (`/health/ready` or `/actuator/health/readiness`) HTTP endpoints suitable for Kubernetes probes. | Scaffold Unit Test & Kubernetes Manifest Check | `Q3` (`ADR-0011`) |
| **`NFR-OPS-002`** | Multi-Node K3s Resource Governance | Every Kubernetes workload manifest MUST define explicit CPU/memory `requests` and `limits` sized to fit within a 3–4 node K3s cluster (`2 vCPU, 3.8 GiB RAM` per VM) without node OOM storms. | Kubernetes Manifest Lint & Deployment Test (`M9`) | `Q2`, `Q3` (`ADR-0011`) |

---

## 6. Architecture Governance Requirements (`NFR-GOV`)

| ID | Category | Requirement | Verification Method | Governing Decision |
| :--- | :--- | :--- | :--- | :--- |
| **`NFR-GOV-001`** | Database-per-Service Isolation | No microservice may connect to, query, or mutate another microservice's PostgreSQL database schema directly. All cross-service interactions MUST occur via versioned HTTP/gRPC APIs or Kafka domain events. | Automated Architecture Test (`tests/architecture/`) & CI Review | `ADR-0001`, `ADR-0002` |
