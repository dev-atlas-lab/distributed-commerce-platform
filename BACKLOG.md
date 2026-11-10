# Product & Engineering Backlog — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-BKL-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

All tasks follow the mandatory lifecycle: `PROPOSED` → `DISCUSSION` → `ACCEPTED` → `IMPLEMENTING` → `IMPLEMENTED` → `VERIFIED` → `DONE`.

---

## 1. Milestone M0 Summary (`Product Discovery & Architecture`)

| Task ID | Title | Owner | Status |
| :--- | :--- | :--- | :--- |
| `DCP-M0-001` | Workspace & Environment Inspection, Product Discovery, DDD Domain Modeling, Architecture Design, 10 ADRs, and M1 Task Breakdown | AI Team + Human Architect | `PROPOSED` (Ready for Human Review) |

---

## 2. Detailed Milestone M1 Tasks (`Foundation & Polyglot Scaffolding`)

> [!IMPORTANT]
> Per Mandatory Rule #1 & #2, M1 tasks establish **only the technical foundation, infrastructure, build toolchains, observability plumbing, database migration runners, and architecture boundary tests**. Zero business domain features are implemented in M1.

---

### Task `DCP-M1-001` — Toolchain Provisioning & Monorepo Workspace Conventions
- **Status**: `PROPOSED`
- **Business Context**: Before any service or UI can be built and verified, the developer workstation/VM needs a repeatable, version-pinned polyglot toolchain (`Java 21`, `Maven 3.9+`, `.NET 10 SDK`, `Python 3.12 + uv`, `Node 22`, `Docker Engine + Compose v2`, `k6`).
- **Technical Context**: Our `Step 1` inspection showed `git` (`2.34.1`) and `node` (`v22.23.4`) are installed on the current ARM64 Ubuntu VM (`vm-anhltn-agy`), while `java`, `mvn`, `dotnet`, `uv`, `docker`, and `k6` are not yet installed.
- **Objective**: Create an idempotent setup script (`scripts/setup-dev-toolchain.sh`), root `.gitignore`, `.editorconfig`, `Makefile`, and `.env.example` so any Ubuntu 22.04/24.04 (`x86_64` or `aarch64`) machine can install/verify the required SDKs cleanly.
- **In Scope**:
  - `scripts/setup-dev-toolchain.sh` with `--check` (dry-run verification) and `--install` modes.
  - Root `.gitignore` (covering Java/Maven, .NET, Python/uv, Node/Vite, Docker, SOPS keys), `.editorconfig`, `.env.example`, and `Makefile`.
- **Out of Scope**: Starting Docker containers or scaffolding application code (covered in `DCP-M1-002` through `DCP-M1-006`).
- **Dependencies**: M0 Approval.
- **Acceptance Criteria**:
  1. `scripts/setup-dev-toolchain.sh --check` reports exact versions of `java (21.x)`, `mvn (3.9+)`, `dotnet (10.0.x)`, `python3 (3.12+)`, `uv`, `node (22.x)`, `docker`, `docker compose`, and `k6`.
  2. `.env.example` contains only safe development placeholder values and zero production secrets.
- **Edge Cases**: Running on `aarch64` (ARM64 Neoverse-N1) vs `x86_64` architecture; script must detect `uname -m` automatically when fetching binaries (`k6`, ` Temurin JDK 21`, `.NET 10`).
- **Security Considerations**: Verify GPG signatures / official apt repositories for Docker, Adoptium Temurin, Microsoft .NET, and Grafana k6; never pipe unverified third-party scripts blindly.
- **Test Cases**:
  - *Positive*: Run `scripts/setup-dev-toolchain.sh --check` after installation → exits `0`.
  - *Negative*: Missing binary simulated in PATH → exits non-zero with clear installation remediation message.
  - *Edge*: Re-running `--install` when tools are already installed → idempotent no-op (`0` errors).
- **Expected Deliverables**: `scripts/setup-dev-toolchain.sh`, `.gitignore`, `.editorconfig`, `.env.example`, `Makefile`.
- **Definition of Done**: All SDKs verified via `--check` and git status clean of untracked artifacts.

---

### Task `DCP-M1-002` — Local Infrastructure Docker Compose & Isolated Multi-DB Bootstrap
- **Status**: `PROPOSED`
- **Business Context**: All 9 services require isolated databases, a Redis cache/Lua engine, an event streaming backbone, object storage for product images, and an email sink for notifications.
- **Technical Context**: Implements `ADR-0002` (1 PostgreSQL 17 instance with 7 isolated databases and least-privilege roles) and `ADR-0010` (Apache Kafka 3.8 in KRaft mode without ZooKeeper), structured with Docker Compose profiles (`infra`, `core-commerce`, `flash-sale`, `ai`, `observability`) to respect the 3.8 GiB VM RAM constraint.
- **Objective**: Create `docker-compose.yml` and `infrastructure/postgres/init-multi-db.sql`, `infrastructure/kafka/init-topics.sh`, and `infrastructure/redis/redis.conf`.
- **In Scope**:
  - `PostgreSQL 17` (`pgvector/pgvector:pg17` image so `ai_agent_db` supports `CREATE EXTENSION vector`) + init script creating `product_db`, `customer_db`, `order_db`, `inventory_db`, `payment_db`, `promotion_db`, `ai_agent_db` and 7 isolated DB users.
  - `Redis 7.4-alpine` with AOF persistence and bounded `maxmemory 256mb`.
  - `Apache Kafka 3.8` in single-node KRaft mode (`bitnami/kafka:3.8` or `apache/kafka:3.8.1`) + topic bootstrap job creating the canonical topics (`*.v1`, `*.retry.1m`, `*.dlq.v1`).
  - `MinIO` (`product-media` bucket bootstrap) + `Mailpit` (local SMTP + web UI).
- **Out of Scope**: Application containers (`M2+`) and full Kubernetes manifests (`M6`).
- **Dependencies**: `DCP-M1-001`.
- **Acceptance Criteria**:
  1. `docker compose --profile infra up -d` brings all infrastructure containers to `healthy` status within `60s`.
  2. Total memory consumption of the `infra` profile stays `< 1.4 GiB` RAM.
  3. Connecting as `order_svc_user` to `order_db` succeeds, while connecting as `order_svc_user` to `inventory_db` fails with `FATAL: permission denied for database "inventory_db"`.
- **Edge Cases**: Container restart idempotency (`init-multi-db.sql` and `init-topics.sh` must use `IF NOT EXISTS` so restarting containers does not fail).
- **Security Considerations**: Revoke `PUBLIC` connect privileges on each service database (`REVOKE CONNECT ON DATABASE inventory_db FROM PUBLIC; GRANT CONNECT ON DATABASE inventory_db TO inventory_svc_user;`).
- **Test Cases**:
  - *Positive*: Automated shell verification script `scripts/verify-infra.sh` tests PG connectivity for all 7 users, Redis `PING`, Kafka produce/consume test message, MinIO bucket check, and Mailpit HTTP API.
  - *Negative*: Cross-database connection attempt between `order_svc_user` and `inventory_db` is rejected by PostgreSQL.
  - *Edge*: Restarting Kafka and Postgres containers preserves existing topics and databases.
- **Expected Deliverables**: `docker-compose.yml`, `infrastructure/postgres/init-multi-db.sql`, `infrastructure/kafka/init-topics.sh`, `infrastructure/redis/redis.conf`, `scripts/verify-infra.sh`.
- **Definition of Done**: `scripts/verify-infra.sh` exits `0` with all health checks and cross-DB isolation assertions passing.

---

### Task `DCP-M1-003` — Java 21 + Spring Boot 3.x Multi-Module Skeleton & Clean Architecture Guardrails
- **Status**: `PROPOSED`
- **Business Context**: Four core services (`product-service`, `order-service`, `inventory-service`, `payment-service`) run on Java 21 + Spring Boot 3.4+. They need consistent dependency management, Flyway migration setup, RFC 9457 `ProblemDetail` exception handling, OpenTelemetry tracing, and ArchUnit Clean Architecture enforcement before business implementation starts in M2.
- **Technical Context**: Uses Maven multi-module layout under `services/java/` with Virtual Threads enabled (`spring.threads.virtual.enabled=true`), `spring.jpa.open-in-view=false`, Actuator liveness/readiness probes, and Testcontainers base test configuration.
- **Objective**: Scaffold `services/java/pom.xml` and the 4 service skeletons (`product-service`, `order-service`, `inventory-service`, `payment-service`) with baseline `V1__init_outbox_inbox.sql` migrations and ArchUnit tests—**without implementing domain business logic**.
- **In Scope**:
  - Parent `services/java/pom.xml` pinning Spring Boot `3.4.x`, Java `21`, Resilience4j, Spring Kafka, Flyway, Micrometer/OpenTelemetry, JUnit 5, Testcontainers, and ArchUnit.
  - Package hierarchy per service: `domain`, `application`, `infrastructure`, `presentation`.
  - Baseline `V1__init_outbox_inbox.sql` Flyway migration in each service.
  - Global `@RestControllerAdvice` producing RFC 9457 `ProblemDetail` with `errorCode` and `traceId`.
  - ArchUnit test (`CleanArchitectureTest.java`) verifying `domain` has zero imports from `org.springframework..`, `jakarta.persistence..`, or `org.apache.kafka..`.
- **Out of Scope**: Product, Order, Inventory, or Payment business aggregates/endpoints (reserved for Human implementation in M2–M4).
- **Dependencies**: `DCP-M1-001`, `DCP-M1-002`.
- **Acceptance Criteria**:
  1. `mvn -f services/java/pom.xml clean verify` compiles all 4 services and passes ArchUnit + Actuator health integration tests.
  2. Each service starts against its dedicated database and runs `V1__init_outbox_inbox.sql`.
- **Edge Cases**: Unhandled validation errors (`MethodArgumentNotValidException`) and malformed JSON (`HttpMessageNotReadableException`) must return uniform `application/problem+json` payloads.
- **Security Considerations**: Actuator endpoints expose only `/actuator/health/**` and `/actuator/prometheus` publicly; sensitive actuator endpoints (`env`, `heapdump`, `beans`) are disabled or restricted.
- **Test Cases**:
  - *Positive*: Context load, Flyway V1 migration execution, and `/actuator/health/readiness` returns `200 UP`.
  - *Negative*: ArchUnit test fails if a dummy class in `domain` imports `org.springframework.stereotype.Service`.
  - *Edge*: Request with invalid header/body triggers RFC 9457 `ProblemDetail` including `traceId`.
- **Expected Deliverables**: `services/java/pom.xml` and skeletal structure for `product-service`, `order-service`, `inventory-service`, `payment-service`.
- **Definition of Done**: `mvn -f services/java/pom.xml clean verify` exits `0`.

---

### Task `DCP-M1-004` — .NET 10 Solution Skeleton (`API Gateway`, `Customer`, `Promotion`, `Notification`)
- **Status**: `PROPOSED`
- **Business Context**: Four services (`api-gateway`, `customer-service`, `promotion-service`, `notification-service`) run on `.NET 10 LTS` (`ASP.NET Core`). They require a unified solution file (`services/dotnet/DistributedCommerce.sln`), centralized package versions (`Directory.Packages.props`), EF Core PostgreSQL wiring, RFC 9457 `ProblemDetails`, OpenTelemetry instrumentation, and `NetArchTest` rules.
- **Technical Context**: Uses `.NET 10`, `YARP` in `api-gateway`, `EF Core + Npgsql`, `FluentValidation`, `StackExchange.Redis`, `Confluent.Kafka`, and `xUnit + Testcontainers`.
- **Objective**: Scaffold `services/dotnet/DistributedCommerce.sln`, source projects, and corresponding `.Tests` projects with health endpoints (`/health/live`, `/health/ready`), `ProblemDetails` middleware, and baseline Outbox/Inbox EF Core configurations—**without implementing business features**.
- **In Scope**:
  - `Directory.Build.props` (`net10.0`, `Nullable=enable`, `ImplicitUsings=enable`, `TreatWarningsAsErrors=true`) and `Directory.Packages.props`.
  - `ApiGateway` with YARP config placeholder, correlation ID middleware, and health checks.
  - `CustomerService`, `PromotionService`, and `NotificationService` skeletons with `NetArchTest` and health checks.
- **Out of Scope**: Customer auth logic, shopping cart endpoints, coupon rules, or Flash Sale Lua implementation (reserved for M2–M4).
- **Dependencies**: `DCP-M1-001`, `DCP-M1-002`.
- **Acceptance Criteria**:
  1. `dotnet build services/dotnet/DistributedCommerce.sln --configuration Release` succeeds with `0` warnings and `0` errors.
  2. `dotnet test services/dotnet/DistributedCommerce.sln` passes all unit, architecture, and health-probe integration tests.
- **Edge Cases**: Missing `X-Correlation-Id` header on incoming Gateway request automatically generates a new UUIDv4 and attaches it to response headers and log scope.
- **Security Considerations**: Gateway strips any incoming external `X-Internal-*` headers before proxying upstream.
- **Test Cases**:
  - *Positive*: `WebApplicationFactory` integration test on each service returns `200 Healthy` on `/health/live` and `/health/ready`.
  - *Negative*: `NetArchTest` verifies domain layer does not reference `Microsoft.EntityFrameworkCore` or `AspNetCore`.
  - *Edge*: Correlation ID middleware preserves caller's `X-Correlation-Id` when valid, or generates a new one when blank/overlong.
- **Expected Deliverables**: `services/dotnet/DistributedCommerce.sln` and 4 .NET service skeletons + test projects.
- **Definition of Done**: `dotnet test` exits `0` with zero compiler warnings.

---

### Task `DCP-M1-005` — Python 3.12+ FastAPI AI Agent Service Skeleton & Guardrail Harness
- **Status**: `PROPOSED`
- **Business Context**: The `ai-agent-service` (`Python 3.12+`, `FastAPI`, `Pydantic v2`, `SQLAlchemy Async + asyncpg + pgvector`, `Alembic`) powers the Shopping and Operations Assistants in M5 and must be scaffolded with strict typing, async health checks, and architectural boundaries in M1.
- **Technical Context**: Managed via `uv` (`pyproject.toml`), checked with `ruff` and `mypy --strict`, tested with `pytest` and `pytest-asyncio`.
- **Objective**: Scaffold `services/python/ai-agent-service/` with FastAPI app factory, RFC 9457 `ProblemDetails` exception handler, OpenTelemetry hooks, `ai_agent_db` (`pgvector`) readiness probe, and unit/architecture tests enforcing zero direct connections to business databases.
- **In Scope**:
  - `pyproject.toml`, `app/main.py`, `app/api/health.py`, `app/core/config.py`, `app/core/errors.py`, `migrations/` (Alembic baseline enabling `vector` extension).
  - `tests/test_health.py` and `tests/test_security_boundary.py`.
- **Out of Scope**: LLM tool execution workflows, RAG ingestion, and chat prompts (reserved for M5).
- **Dependencies**: `DCP-M1-001`, `DCP-M1-002`.
- **Acceptance Criteria**:
  1. `ruff check`, `mypy --strict`, and `pytest` pass with `0` errors.
  2. `/health/live` and `/health/ready` (checking `ai_agent_db` + `pgvector` extension presence) return `200 OK`.
- **Edge Cases**: Invalid JSON or Pydantic validation error on any endpoint returns RFC 9457 `application/problem+json` with `traceId`.
- **Security Considerations**: Configuration validator rejects startup if `DATABASE_URL` points to any database other than `ai_agent_db`.
- **Test Cases**:
  - *Positive*: FastAPI `AsyncClient` tests `/health/live` and `/health/ready`.
  - *Negative*: Config test attempting to pass `order_db` or `inventory_db` into `Settings` raises `ValidationError`.
  - *Edge*: Unhandled validation error formats as RFC 9457 `ProblemDetails`.
- **Expected Deliverables**: `services/python/ai-agent-service/` skeleton and test suite.
- **Definition of Done**: `ruff`, `mypy --strict`, and `pytest` all exit `0`.

---

### Task `DCP-M1-006` — React 19 + TypeScript Frontend Shell (Storefront & Admin Layouts + API Client)
- **Status**: `PROPOSED`
- **Business Context**: The frontend is a first-class deliverable comprising both a Customer Storefront and an Admin/Operations Portal. It needs a rock-solid foundation: strict TypeScript, Tailwind CSS design system primitives, React Router v7 dual-layout routing, TanStack Query error/retry integration, Zustand auth/UI stores, and Vitest + Playwright + `axe-core` testing harnesses.
- **Technical Context**: Located in `frontend/`, using `React 19`, `TypeScript 5.x`, `Vite 6`, `TanStack Query v5`, `Zustand v5`, `Tailwind CSS`, `Vitest`, `React Testing Library`, and `Playwright`.
- **Objective**: Scaffold `frontend/` with Storefront and Admin shell layouts, typed HTTP client (`ProblemDetails` parser + automatic `Idempotency-Key` & `X-Correlation-Id` header injection), reusable state primitives (`LoadingSkeleton`, `ErrorBannerWithRetry`, `EmptyState`), and automated unit + E2E accessibility tests.
- **In Scope**:
  - `frontend/` Vite + TypeScript setup (`strict: true`, `noUncheckedIndexedAccess: true`).
  - Typed API client (`src/lib/api-client.ts`) parsing RFC 9457 `ProblemDetails`.
  - Storefront shell (`/`, `/flash-sales`, `/cart`, `/orders`) and Admin shell (`/admin/catalog`, `/admin/inventory`, `/admin/flash-sales`, `/admin/ops`) with responsive navigation and route guards.
  - Component tests (Vitest) + Playwright smoke & `axe-core` zero-violation check.
- **Out of Scope**: Full catalog CRUD forms, checkout forms, or Flash Sale arena business logic (reserved for M2–M4).
- **Dependencies**: `DCP-M1-001`.
- **Acceptance Criteria**:
  1. `npm --prefix frontend run typecheck`, `lint`, `test`, and `build` pass with `0` errors.
  2. Playwright E2E test verifies Storefront and Admin shells render responsively on desktop (`1280x800`) and mobile (`375x812`) with `0` `axe-core` accessibility violations.
- **Edge Cases**: Network timeout or HTTP `503` / `409 ProblemDetails` response in `api-client` surfaces structured `errorCode`, `detail`, and `traceId` to the `ErrorBannerWithRetry` component.
- **Security Considerations**: Never store raw sensitive tokens in vulnerable globals; sanitize all dynamic text; enforce strict CSP-compatible rendering.
- **Test Cases**:
  - *Positive*: Storefront & Admin layout rendering, keyboard navigation, and API client `GET`/`POST` success.
  - *Negative*: API client receives `409 ProblemDetails` and maps `errorCode` + `traceId` accurately; unauthorized user visiting `/admin/*` redirects to login/forbidden state.
  - *Edge*: Automatic `Idempotency-Key` header generation on `POST` requests preserves the same key across TanStack Query automatic retries of the same mutation!
- **Expected Deliverables**: `frontend/` application foundation, unit tests, and Playwright E2E + `axe` suite.
- **Definition of Done**: `typecheck`, `lint`, `test`, `build`, and `e2e` pass with zero errors.

---

### Task `DCP-M1-007` — GitHub Actions CI Pipeline & Contract Linting Gate
- **Status**: `PROPOSED`
- **Business Context**: Every pull request and milestone must be verified automatically against our quality gates so broken builds, architecture violations, or invalid API/event schemas can never merge silently.
- **Technical Context**: GitHub Actions workflow (`.github/workflows/ci.yml`) + local verification runner (`scripts/run-ci-checks.sh`).
- **Objective**: Create `.github/workflows/ci.yml` and `scripts/run-ci-checks.sh` executing Contract Validation (OpenAPI + JSON Schema), Frontend checks, Java checks, .NET checks, and Python checks.
- **In Scope**:
  - `.github/workflows/ci.yml` with path-filtered / parallel jobs (`contracts`, `frontend`, `java-services`, `dotnet-services`, `python-ai-service`).
  - `scripts/run-ci-checks.sh` so the exact same pipeline can be run locally before pushing.
- **Out of Scope**: CD deployment to on-prem Kubernetes (`M6`).
- **Dependencies**: `DCP-M1-003`, `DCP-M1-004`, `DCP-M1-005`, `DCP-M1-006`.
- **Acceptance Criteria**:
  1. `scripts/run-ci-checks.sh` validates OpenAPI (`docs/api-contracts/`), JSON Schemas (`docs/event-contracts/`), Java, .NET, Python, and React builds.
  2. Intentionally breaking an OpenAPI contract or ArchUnit rule causes `scripts/run-ci-checks.sh` to fail with a non-zero exit code.
- **Edge Cases**: CI caching for Maven (`~/.m2`), NuGet (`~/.nuget/packages`), `uv` cache, and `npm` cache to keep CI runs fast.
- **Security Considerations**: Pin GitHub Actions permissions (`permissions: contents: read`) and never echo environment secrets in workflow logs.
- **Test Cases**:
  - *Positive*: Clean run of `scripts/run-ci-checks.sh` exits `0`.
  - *Negative*: Syntax error in `event-envelope.v1.schema.json` fails the contract lint step immediately.
- **Expected Deliverables**: `.github/workflows/ci.yml`, `scripts/run-ci-checks.sh`.
- **Definition of Done**: Full local CI check passes end-to-end.

---

## 3. High-Level Backlog Epics for M2–M7 (Elaborated Prior to Each Milestone)

| Milestone | Epic ID | Epic Title | Initial Status |
| :--- | :--- | :--- | :--- |
| **M2** | `DCP-M2-E01` | Customer Identity (`RS256` JWT + JWKS), Profile, Addresses & Redis Shopping Cart (`.NET 10`) | `PROPOSED` |
| **M2** | `DCP-M2-E02` | Product Catalog (Category Tree, SPU/SKU, MinIO Media, PG 17 FTS + Faceted Search) (`Java 21`) | `PROPOSED` |
| **M2** | `DCP-M2-E03` | Synchronous Baseline Order Creation, Idempotency Key & Order History (`Java 21`) | `PROPOSED` |
| **M2** | `DCP-M2-E04` | Storefront Catalog/Cart/Checkout UI & Admin Product/SKU Portal (`React 19`) | `PROPOSED` |
| **M3** | `DCP-M3-E01` | Inventory Service Stock Ledger, Conditional Atomic Reservation & Expiry Worker (`Java 21`) | `PROPOSED` |
| **M3** | `DCP-M3-E02` | Transactional Outbox Relay & Idempotent Inbox Consumer Framework (`Java 21` & `.NET 10`) | `PROPOSED` |
| **M3** | `DCP-M3-E03` | Order Fulfillment Saga Orchestrator & Compensating Transactions (`Java 21`) | `PROPOSED` |
| **M3** | `DCP-M3-E04` | Notification Service Kafka Consumer, Non-Blocking Retry Topics, DLQ & Admin Replay UI (`.NET 10`) | `PROPOSED` |
| **M4** | `DCP-M4-E01` | Payment Service Simulator, Signed Webhooks, Timeout Sweeper & Late-Payment Auto-Refund (`Java 21`) | `PROPOSED` |
| **M4** | `DCP-M4-E02` | Promotion Service Coupon Engine & Flash Sale Redis Lua Atomic Gate + Reconciliation Worker (`.NET 10`) | `PROPOSED` |
| **M4** | `DCP-M4-E03` | Redis Cache-Aside, Single-Flight Stampede Protection & Storefront Flash Sale Live Arena UI | `PROPOSED` |
| **M5** | `DCP-M5-E01` | Python AI Shopping Assistant (JWT-Bound Tool Calling, `pgvector` Hybrid RAG, Streaming SSE) | `PROPOSED` |
| **M5** | `DCP-M5-E02` | Python AI Operations Assistant, HITL Approval Workflow, Guardrails & 50-Case Eval Suite | `PROPOSED` |
| **M6** | `DCP-M6-E01` | Multi-VM Kubernetes Cluster (`K3s`/`kubeadm`), MetalLB, Ingress-NGINX, Storage & SOPS Secrets | `PROPOSED` |
| **M6** | `DCP-M6-E02` | Helm Charts, Argo CD GitOps Pipeline & Full LGTM/OTel Observability Stack | `PROPOSED` |
| **M7** | `DCP-M7-E01` | 7-Suite `k6` Benchmarks, JVM/.NET/PG Profiling, Optimization Retests & 10 Chaos Scenarios | `PROPOSED` |
