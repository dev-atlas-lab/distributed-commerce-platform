# M0.3.1 — Polyglot Source Foundation Audit (`M0_3_1_SOURCE_FOUNDATION_AUDIT.md`)

**Baseline Audited Commit:** `c0587d3` (`M0.3 — Architecture Freeze and Source Foundation`)
**Audit Date:** 2026-04-11
**Scope:** Actual source code (`src/`, `tests/`, `scripts/`, `pom.xml`, `DistributedCommerce.sln`, `pyproject.toml`) and architectural alignment against [`DECISION_REGISTER.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DECISION_REGISTER.md), [`REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/REQUIREMENTS.md), [`NON_FUNCTIONAL_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/NON_FUNCTIONAL_REQUIREMENTS.md), [`ADR-0001`–`ADR-0011`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/README.md), and [`SPEC.md`](file:///home/anhltn/projects/distributed-commerce-platform/SPEC.md).

---

## Executive Summary of Audit Findings

| Audit ID | Area | Initial Status (`c0587d3`) | Post-`M0.3.1` Status | Summary |
| :--- | :--- | :--- | :--- | :--- |
| **`AUD-01`** | Conceptual Architecture Layers (`Api`, `Application`, `Domain`, `Infrastructure`) | `WARNING` | `PASS` | In `c0587d3`, services contained only entrypoint and OpenAPI config classes without explicit `api`/`application`/`domain`/`infrastructure` package/namespace boundaries or automated dependency-direction tests. Fixed in `M0.3.1` across Java, .NET, and Python with automated enforcement in [`ArchitectureBoundaryTest.java`](file:///home/anhltn/projects/distributed-commerce-platform/tests/architecture/src/test/java/com/devatlas/commerce/architecture/ArchitectureBoundaryTest.java). |
| **`AUD-02`** | Python Strict Type Checking (`mypy --strict` Liskov Override Violation) | `BLOCKER` | `PASS` | Running `mypy --strict` against [`src/building-blocks/python/src/commerce_common/__init__.py`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/__init__.py) failed with 3 errors because `CorrelationIdMiddleware.dispatch` typed `call_next` as synchronous `Callable[[Request], Response]` instead of Starlette's async `RequestResponseEndpoint`. Fixed in `M0.3.1` and added `mypy` to [`scripts/verify-foundation.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/verify-foundation.sh). |
| **`AUD-03`** | Java Test Constructor Injection Convention | `WARNING` | `PASS` | The four `@SpringBootTest` classes used `@Autowired private MockMvc mockMvc;` field injection instead of constructor injection. Refactored to constructor injection in `M0.3.1`. |
| **`AUD-04`** | Bounded Context Mapping & Naming Aliases | `WARNING` | `PASS` | All 9 deployables in `src/` map 1-to-1 to accepted bounded contexts (`zero` unapproved services). Documented canonical naming aliases (`catalog` / `catalog-service` = `product-service` in early `M0.1` prose; `ai-worker` / `commerce-ai-worker` = `ai-agent-service`). |
| **`AUD-05`** | Shared Building Blocks Dependency Hygiene | `WARNING` | `PASS` | Removed unused transitive dependencies (`spring-boot-starter-actuator`, `micrometer-tracing-bridge-otel` from `commerce-building-blocks`; `Microsoft.OpenApi` from `Commerce.BuildingBlocks`; and 4 service `<ProjectReference>` entries from `Commerce.BuildingBlocks.Tests`). |
| **`AUD-06`** | Promotion Stored-Procedure Security (`CH-01`) | `NEEDS_EVIDENCE` | `NEEDS_EVIDENCE` (Docs Hardened) | Hardened [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md), [`REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/REQUIREMENTS.md), and [`NON_FUNCTIONAL_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/NON_FUNCTIONAL_REQUIREMENTS.md) with `REVOKE CREATE ON SCHEMA public FROM PUBLIC, promotion_app_role`, `REVOKE ALL ON FUNCTION ... FROM PUBLIC`, and explicit `promotion_migrator` / `promotion_proc_owner` / `promotion_app_role` / `promotion_dba_admin` separation. Remains `NEEDS_EVIDENCE` until `M1` SQL migrations and role tests are implemented. |
| **`AUD-07`** | Consumer Version-Gap Ordering Specification (`CH-04`) | `WARNING` | `PASS` (Design) / `NEEDS_EVIDENCE` (Runtime) | Specified the concrete bounded version-gap strategy (`inbox_deferred_events` durable table, contiguous drain on gap fill, `max_deferred_per_aggregate = 64`, `max_gap_wait_duration = 5m`, transition to `EXPIRED_QUARANTINED` + `<topic>.dlq` diagnostic alert `SEQUENCE_GAP_TIMEOUT`). |

---

## 1. Architecture Structure Audit

### 1.1 Findings on Commit `c0587d3` (`AUD-01`: `WARNING` -> Fixed to `PASS`)
- **Inspection of `c0587d3`**:
  - Java services (`catalog`, `inventory`, `order`, `payment`) contained only `<Service>Application.java` and `config/OpenApiConfiguration.java`.
  - `.NET 10` services (`customer`, `promotion`, `notification`) contained only `Program.cs` and `appsettings.json`.
  - Python `ai-worker` contained only `src/ai_worker/__init__.py` and `src/ai_worker/main.py`.
  - [`ArchitectureBoundaryTest.java`](file:///home/anhltn/projects/distributed-commerce-platform/tests/architecture/src/test/java/com/devatlas/commerce/architecture/ArchitectureBoundaryTest.java) checked top-level folder existence (`src/services/catalog`, etc.) but did **not** verify internal conceptual layers or `Domain` dependency isolation.
- **Remediation Applied in `M0.3.1` (Idiomatic per Language)**:
  1. **Java 21 Services (`catalog`, `inventory`, `order`, `payment`)**:
     - Established idiomatic Java subpackages with documented `package-info.java` contracts:
       - `com.devatlas.commerce.<service>.api` (Presentation / Inbound REST adapters)
       - `com.devatlas.commerce.<service>.application` (Use-case handlers & ports)
       - `com.devatlas.commerce.<service>.domain` (Pure domain model — zero framework/DB/broker imports)
       - `com.devatlas.commerce.<service>.infrastructure` (Outbound persistence, Kafka/Outbox, Redis, configuration)
  2. **.NET 10 Services (`customer`, `promotion`, `notification`, and `api-gateway`)**:
     - Established idiomatic C# PascalCase layer directories and namespaces (`Commerce.<Service>.Api`, `Commerce.<Service>.Application`, `Commerce.<Service>.Domain`, `Commerce.<Service>.Infrastructure`) in `customer`, `promotion`, and `notification`.
     - Kept `api-gateway` (`Commerce.ApiGateway`) as a lightweight YARP reverse-proxy edge gateway (`ADR-0001`, `ADR-0006`) without artificial domain/repository layers.
  3. **Python 3.12+ Worker (`ai-worker`)**:
     - Established idiomatic Python snake_case subpackages under `src/ai_worker/`: `ai_worker.api`, `ai_worker.application`, `ai_worker.domain`, and `ai_worker.infrastructure`.
  4. **Automated Dependency-Direction Enforcement**:
     - Expanded [`ArchitectureBoundaryTest.java`](file:///home/anhltn/projects/distributed-commerce-platform/tests/architecture/src/test/java/com/devatlas/commerce/architecture/ArchitectureBoundaryTest.java) with:
       - `shouldDefineConceptualArchitectureLayersForEveryService()`
       - `domainLayersMustNotDependOnOuterLayersOrFrameworks()` (verifying zero imports of Spring, JPA, Servlet, ASP.NET Core, EF Core, FastAPI, SQLAlchemy, PostgreSQL drivers, Redis, Kafka, LLM SDKs, or outer `api`/`application`/`infrastructure` packages inside any `domain`/`Domain` directory).

---

## 2. Language-Native Conventions Audit

### 2.1 Java 21 (`PASS` after `AUD-03` Fix)
- **Checked**:
  - Package naming (`lowercase` reverse-DNS `com.devatlas.commerce.<context>.<layer>`): **`PASS`**.
  - Class/method naming (`PascalCase` types, `camelCase` methods, `UPPER_SNAKE_CASE` constants): **`PASS`**.
  - Constructor injection: [`FaultInjectionStartupGuard.java`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/chaos/FaultInjectionStartupGuard.java) uses constructor injection (`PASS`). The 4 `@SpringBootTest` classes in `c0587d3` used `@Autowired private MockMvc mockMvc;` field injection (`AUD-03: WARNING`), which was refactored to constructor injection (`@Autowired <Service>ApplicationTest(MockMvc mockMvc)`) in `M0.3.1` (**`PASS`**).

### 2.2 .NET 10 (`PASS`)
- **Checked**:
  - Namespace & type naming (`PascalCase`, file-scoped namespaces `namespace Commerce...;`): **`PASS`**.
  - `Async` suffix & `CancellationToken` support: `CorrelationIdMiddleware.InvokeAsync(HttpContext context)` and `FaultInjectionStartupGuard.StartAsync(CancellationToken)` / `StopAsync(CancellationToken)` follow standard ASP.NET Core / `IHostedService` conventions: **`PASS`**.
  - Nullable reference types & warnings-as-errors: `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` enforced globally in [`Directory.Build.props`](file:///home/anhltn/projects/distributed-commerce-platform/Directory.Build.props): **`PASS`**.

### 2.3 Python 3.12+ (`BLOCKER` in `c0587d3` -> Fixed to `PASS`)
- **Checked**:
  - `snake_case` modules/functions (`verify_fault_injection_guard`, `register_problem_details_handlers`, `create_app`), `PascalCase` classes (`CorrelationIdMiddleware`), `src/` package layout: **`PASS`**.
  - **Strict Type Hints (`AUD-02: BLOCKER` Fixed)**:
    - In `c0587d3`, [`scripts/verify-foundation.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/verify-foundation.sh) ran `pytest` and `ruff check`, but omitted `mypy`.
    - When `mypy src tests ../../building-blocks/python/src` was executed during this audit, it failed with 3 errors in [`src/building-blocks/python/src/commerce_common/__init__.py`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/__init__.py):
      - `Argument 2 of "dispatch" is incompatible with supertype "starlette.middleware.base.BaseHTTPMiddleware"; supertype defines the argument type as "Callable[[Request[State]], Awaitable[Response]]" [override]`
    - **Fix**: Updated `CorrelationIdMiddleware.dispatch` to use `RequestResponseEndpoint` from `starlette.middleware.base` and added `mypy src tests ../../building-blocks/python/src` to [`scripts/verify-foundation.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/verify-foundation.sh). `mypy --strict` now passes with `0` errors across all Python files (**`PASS`**).

### 2.4 Language-Independent Contracts (`PASS`)
- Verified [`docs/api-contracts/order-and-flashsale.v1.openapi.yaml`](file:///home/anhltn/projects/distributed-commerce-platform/docs/api-contracts/order-and-flashsale.v1.openapi.yaml), [`docs/event-contracts/event-envelope.v1.schema.json`](file:///home/anhltn/projects/distributed-commerce-platform/docs/event-contracts/event-envelope.v1.schema.json), and the RFC 9457 `ProblemDetails` JSON error fields (`type`, `title`, `status`, `detail`, `instance`, `service`, `correlationId`, `timestamp`) across Java, .NET, and Python: **`PASS`**.

---

## 3. Service Boundaries Audit (`AUD-04`)

| Source Path | Build Artifact / Project Name | Runtime | Governing Bounded Context (`DECISION_REGISTER.md` / `REQUIREMENTS.md` / `ADR-0001`) | Audit Status |
| :--- | :--- | :--- | :--- | :--- |
| [`src/gateways/api-gateway`](file:///home/anhltn/projects/distributed-commerce-platform/src/gateways/api-gateway/Commerce.ApiGateway/Commerce.ApiGateway.csproj) | `Commerce.ApiGateway` | `.NET 10` (`YARP`) | Edge API Gateway (`ADR-0001`, `ADR-0006`, `CH-05`) | **`PASS`** |
| [`src/services/catalog`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/catalog/pom.xml) | `catalog-service` | `Java 21` (`Spring Boot 3.4`) | Catalog & Search (`FR-CAT-001..003`, `ADR-0007`; referred to as `product-service` in early `M0.1` prose) | **`PASS`** *(Alias Noted)* |
| [`src/services/inventory`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/inventory/pom.xml) | `inventory-service` | `Java 21` (`Spring Boot 3.4`) | Inventory & Stock Reservation (`FR-INV-001..003`, `ADR-0005`) | **`PASS`** |
| [`src/services/order`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/order/pom.xml) | `order-service` | `Java 21` (`Spring Boot 3.4`) | Order Management & Fulfillment Saga (`FR-ORD-001..004`, `CH-02`, `ADR-0004`) | **`PASS`** |
| [`src/services/payment`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/payment/pom.xml) | `payment-service` | `Java 21` (`Spring Boot 3.4`) | Payment Lifecycle & Webhooks (`FR-PAY-001..004`, `CH-02`, `ADR-0004`) | **`PASS`** |
| [`src/services/customer`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/customer/Commerce.Customer.Api/Commerce.Customer.Api.csproj) | `Commerce.Customer.Api` | `.NET 10` (`ASP.NET Core`) | Customer, Identity & Cart (`FR-CUS-001..003`, `Q5`, `CH-05`, `ADR-0006`) | **`PASS`** |
| [`src/services/promotion`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/promotion/Commerce.Promotion.Api/Commerce.Promotion.Api.csproj) | `Commerce.Promotion.Api` | `.NET 10` (`ASP.NET Core`) | Promotion, Coupons & Flash Sale Gate (`FR-PRO-001..005`, `Q4`, `CH-01`, `ADR-0005`) | **`PASS`** |
| [`src/services/notification`](file:///home/anhltn/projects/distributed-commerce-platform/src/services/notification/Commerce.Notification.Api/Commerce.Notification.Api.csproj) | `Commerce.Notification.Api` | `.NET 10` (`ASP.NET Core`) | Asynchronous Notification Delivery (`ADR-0001`, `ADR-0004`) | **`PASS`** |
| [`src/workers/ai-worker`](file:///home/anhltn/projects/distributed-commerce-platform/src/workers/ai-worker/pyproject.toml) | `commerce-ai-worker` | `Python 3.12+` (`FastAPI`) | AI Shopping & Operations Assistant (`FR-AI-001..003`, `Q7`, `CH-06`, `ADR-0008`; referred to as `ai-agent-service` in early `M0.1` prose) | **`PASS`** *(Alias Noted)* |

- **Unmapped or Invented Services**: **`0`** (`PASS`).

---

## 4. Shared Building Blocks Audit (`AUD-05`: `WARNING` -> Fixed to `PASS`)

| Shared Library | Retained Cross-Cutting Technical Components | Issues Found in `c0587d3` & Remediations Applied in `M0.3.1` | Audit Status |
| :--- | :--- | :--- | :--- |
| [`src/building-blocks/java`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/pom.xml) (`commerce-building-blocks`) | `CorrelationIdFilter`, `GlobalProblemDetailsExceptionHandler`, `FaultInjectionStartupGuard`, `CommerceCommonAutoConfiguration` | **Issue**: `pom.xml` declared `spring-boot-starter-actuator` and `micrometer-tracing-bridge-otel` even though no class in `commerce-building-blocks` referenced them.<br>**Fix**: Removed both unused dependencies from `src/building-blocks/java/pom.xml`. Zero business/domain logic present. | **`PASS`** |
| [`src/building-blocks/dotnet/Commerce.BuildingBlocks`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Commerce.BuildingBlocks.csproj) | `CorrelationIdMiddleware`, `FaultInjectionStartupGuard`, `PlatformServiceExtensions` | **Issue 1**: `Commerce.BuildingBlocks.csproj` had `<PackageReference Include="Microsoft.OpenApi" Version="2.13.0" />` only to override a transitive warning in the downstream Web API projects.<br>**Issue 2**: `Commerce.BuildingBlocks.Tests.csproj` referenced all 4 downstream service projects (`Commerce.ApiGateway`, `Commerce.Customer.Api`, `Commerce.Promotion.Api`, `Commerce.Notification.Api`), inverting dependency direction.<br>**Fix**: Moved `Microsoft.OpenApi` `2.13.0` to the 4 Web API `.csproj` files that use `Microsoft.AspNetCore.OpenApi`, and removed the 4 service `<ProjectReference>` entries from `Commerce.BuildingBlocks.Tests.csproj`. | **`PASS`** |
| [`src/building-blocks/python`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/pyproject.toml) (`commerce-common`) | `verify_fault_injection_guard`, `CorrelationIdMiddleware`, `register_problem_details_handlers` | **Issue**: `CorrelationIdMiddleware.dispatch` type annotation failed `mypy --strict`.<br>**Fix**: Fixed type signature to `RequestResponseEndpoint`. Zero business/domain logic present. | **`PASS`** |

---

## 5. Promotion Stored-Procedure Security Review (`CH-01` — `AUD-06`)

> **Verification Honesty Rule**: Because no PostgreSQL migration scripts (`fn_mp01`–`fn_mp08`) or database role provisioning scripts have been implemented or executed against a live PostgreSQL instance yet (`M1+` scope), runtime security verification is classified as **`NEEDS_EVIDENCE`**.

### 5.1 Six-Point Security Audit of the `CH-01` Specification

| Security Control | Audit of `M0.3` Documentation | Gap Identified & Fixed in `M0.3.1` | Current Status |
| :--- | :--- | :--- | :--- |
| **1. `SECURITY DEFINER` Ownership** | Specified `promotion_proc_owner` with `NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE` owning both the protected tables and `fn_mp01`–`fn_mp08`. | None (design is sound; prevents superuser escalation). | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |
| **2. `search_path` Safety** | Specified `SET search_path = pg_catalog, public` on every `SECURITY DEFINER` function. | Added requirement that all object references inside `fn_mp01`–`fn_mp08` must be explicitly schema-qualified (`public.<table_name>`) in addition to `SET search_path = pg_catalog, public`. | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |
| **3. `public` Schema `CREATE` Privileges** | **Gap in `c0587d3`**: Did not explicitly require revoking `CREATE` on schema `public` from `PUBLIC` and `promotion_app_role`. If `promotion_app_role` retained `CREATE ON SCHEMA public`, it could shadow unqualified objects when `public` is in `search_path`. | **Fixed in [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md), [`REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/REQUIREMENTS.md), and [`NON_FUNCTIONAL_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/NON_FUNCTIONAL_REQUIREMENTS.md)**: Added mandatory `REVOKE CREATE ON SCHEMA public FROM PUBLIC, promotion_app_role; GRANT USAGE ON SCHEMA public TO promotion_app_role;`. | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |
| **4. Function `EXECUTE` Grants** | **Gap in `c0587d3`**: Specified `GRANT EXECUTE ON FUNCTION ... TO promotion_app_role`, but omitted the fact that **PostgreSQL grants `EXECUTE` on newly created functions to `PUBLIC` by default**. Without revoking `EXECUTE` from `PUBLIC`, any role in `promotion_db` inherits `EXECUTE` via `PUBLIC`. | **Fixed in [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md), [`REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/REQUIREMENTS.md), and [`NON_FUNCTIONAL_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/NON_FUNCTIONAL_REQUIREMENTS.md)**: Added mandatory `ALTER DEFAULT PRIVILEGES FOR ROLE promotion_proc_owner IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;` and `REVOKE ALL ON FUNCTION fn_mp01..fn_mp08 FROM PUBLIC;` prior to `GRANT EXECUTE ... TO promotion_app_role`. | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |
| **5. Application Role Privileges (`promotion_app_role`)** | Specified `REVOKE INSERT, UPDATE, DELETE` on `flash_sale_campaigns`, `flash_sale_claims`, `flash_sale_items`, `outbox_messages`, `idempotency_records`. | Expanded to explicitly revoke `INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` from `PUBLIC` and `promotion_app_role` on all protected tables. | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |
| **6. Migration / Admin Role Separation** | Mentioned migration/admin exceptions conceptually. | Formalized the 4-role separation matrix in [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md):<br>• `promotion_migrator` (`LOGIN`, CI/CD DDL migration job; assigns ownership to `promotion_proc_owner`)<br>• `promotion_proc_owner` (`NOLOGIN NOSUPERUSER`, owns tables & `SECURITY DEFINER` functions)<br>• `promotion_app_role` (`LOGIN NOSUPERUSER`, runtime service pool; `EXECUTE` only on `fn_mp01`–`fn_mp08`)<br>• `promotion_dba_admin` (break-glass human DBA role). | `DESIGN_ACCEPTED` / **`NEEDS_EVIDENCE`** (SQL in `M1`) |

---

## 6. Consumer Ordering & Concrete Bounded Version-Gap Strategy (`CH-04` — `AUD-07`)

### 6.1 Audit of `c0587d3` Specification (`WARNING` -> Fixed to `PASS` in Design)
In `c0587d3`, `CH-04` stated that when a consumer receives an out-of-order event (`incoming.version > last_applied_version + 1`), the event is *"buffered/deferred for bounded retry (`SEQUENCE_GAP_DETECTED`); never applied early and never skipped"*, without defining the exact storage mechanism, per-aggregate capacity bound, wait timeout, or partition non-blocking behavior.

### 6.2 Concrete Bounded Version-Gap Handling Specification (Frozen in [`ADR-0003`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0003-transactional-outbox-and-inbox-idempotency.md) & [`REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/REQUIREMENTS.md))

1. **Single-Transaction Version Gate at the Consumer Boundary**:
   For each incoming event $E = (\text{event\_id}, \text{aggregate\_type}, \text{aggregate\_id}, \text{incoming\_version})$, the consumer opens a local PostgreSQL transaction and locks the target aggregate projection's version state (`SELECT last_applied_version FROM <aggregate_projection> WHERE aggregate_id = $1 FOR UPDATE`, defaulting to `0` if not yet created):
   - **Case A (`incoming_version <= last_applied_version` — Stale or Duplicate)**:
     - Insert `(event_id, consumer_group, 'IGNORED_STALE')` into `inbox_messages ON CONFLICT DO NOTHING`.
     - Commit local transaction and acknowledge Kafka offset (`Idempotent No-Op`).
   - **Case B (`incoming_version == last_applied_version + 1` — Expected Next Sequential Event)**:
     - Insert `(event_id, consumer_group, 'APPLIED')` into `inbox_messages`.
     - Apply the state transition to the aggregate projection and set `last_applied_version = incoming_version`.
     - **Contiguous Deferral Drain**: Query `inbox_deferred_events` for the same `(consumer_group, aggregate_type, aggregate_id)` where `status = 'DEFERRED' ORDER BY aggregate_version ASC FOR UPDATE`. While the head deferred row satisfies `deferred.aggregate_version == last_applied_version + 1`, apply it in order, mark it `status = 'APPLIED'`, and increment `last_applied_version`.
     - Commit local transaction and acknowledge Kafka offset.
   - **Case C (`incoming_version > last_applied_version + 1` — Out-of-Order Version Gap Detected)**:
     - **Do NOT block the Kafka consumer partition** (which would cause head-of-line blocking for unrelated aggregates on the same partition) and **do NOT apply or skip the event**.
     - Insert the event into the consumer's durable local deferral buffer table `inbox_deferred_events`:
       ```sql
       CREATE TABLE inbox_deferred_events (
           consumer_group      VARCHAR(128) NOT NULL,
           aggregate_type      VARCHAR(64)  NOT NULL,
           aggregate_id        VARCHAR(128) NOT NULL,
           aggregate_version   BIGINT       NOT NULL,
           event_id            UUID         NOT NULL,
           topic               VARCHAR(128) NOT NULL,
           payload             JSONB        NOT NULL,
           headers             JSONB        NOT NULL,
           first_seen_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
           last_checked_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
           retry_count         INTEGER      NOT NULL DEFAULT 0,
           status              VARCHAR(32)  NOT NULL DEFAULT 'DEFERRED'
                               CHECK (status IN ('DEFERRED', 'APPLIED', 'EXPIRED_QUARANTINED')),
           PRIMARY KEY (consumer_group, aggregate_type, aggregate_id, aggregate_version)
       );
       ```
     - Commit local transaction and acknowledge Kafka offset so the partition continues processing subsequent messages (including the delayed missing version `last_applied_version + 1` when it arrives!).

2. **Explicit Bounds & Escalation Policy**:
   - **Bound 1 — Per-Aggregate Buffered Row Limit (`max_deferred_per_aggregate = 64`)**:
     - If an aggregate already has `64` rows in `status = 'DEFERRED'`, the consumer transitions that aggregate's deferred rows to `EXPIRED_QUARANTINED` and emits a `SEQUENCE_GAP_OVERFLOW` alert to `<topic>.dlq` to prevent unbounded table growth.
   - **Bound 2 — Sweeper Retry Schedule (`5s` base, exponential backoff `5s, 15s, 30s, 60s`, `max_retries = 20`)**:
     - A background sweeper periodically re-checks `DEFERRED` rows in case a concurrent transaction filled the gap.
   - **Bound 3 — Maximum Wait Duration (`max_gap_wait_duration = 5 minutes`)**:
     - If `NOW() - first_seen_at > INTERVAL '5 minutes'` and `last_applied_version + 1` has still not arrived, the sweeper transitions all `DEFERRED` rows for `(consumer_group, aggregate_type, aggregate_id)` to `status = 'EXPIRED_QUARANTINED'`, publishes a diagnostic payload to `<topic>.dlq` (`reason = 'SEQUENCE_GAP_TIMEOUT'`, `expected_version = last_applied_version + 1`, `first_seen_at`), and increments `commerce_inbox_sequence_gap_quarantined_total` so operators/reconcilers can replay the missing version from the producer's `outbox_messages`.
     - **Strict Invariant**: Under no circumstance may the consumer skip `last_applied_version + 1` and apply `incoming_version > last_applied_version + 1` onto stale state.
