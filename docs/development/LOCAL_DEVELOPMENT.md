# Local Development Guide (`LOCAL_DEVELOPMENT.md`)

**Milestone:** `M0.3` — Architecture Freeze and Source Foundation
**Last Updated:** 2026-04-11

This guide documents the required toolchains, repository structure, build/test commands, coding conventions, and local runtime instructions for `distributed-commerce-platform`.

---

## 1. Required Toolchains

| Runtime / Tool | Required Version | Verified Host Version (`M0.3`) | Purpose |
| :--- | :--- | :--- | :--- |
| **Java JDK** | `Java 21 LTS` | `OpenJDK 21.0.13` | `catalog`, `inventory`, `order`, `payment`, `commerce-building-blocks` |
| **Apache Maven** | `Maven 3.6+ / 3.9+` | `Apache Maven 3.6.3` | Multi-module Java build & dependency management |
| **.NET SDK** | `.NET 10.0 SDK` | `.NET SDK 10.0.404` | `api-gateway` (`YARP`), `customer`, `promotion`, `notification`, `Commerce.BuildingBlocks` |
| **Python & `uv`** | `Python 3.12+` & `uv 0.5+` | `Python 3.12.16` & `uv 0.13.7` | `ai-worker` (`FastAPI`) and `commerce-common` (`src/building-blocks/python`) |
| **Docker & Compose** | `Docker 24+` & `Compose v2` | Host Docker Engine | Local PostgreSQL 17, Redis 7.4, Apache Kafka 3.8 (KRaft), MinIO, OTel (`M1+`) |

Ensure `$HOME/.local/bin` (for `uv`) and `$HOME/.dotnet` (for `dotnet`) are on your `PATH`:
```bash
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"
```

---

## 2. Monorepo Structure Overview

```text
distributed-commerce-platform/
├── pom.xml                           # Root Maven parent POM (Java 21 + Spring Boot 3.4)
├── DistributedCommerce.sln           # Root .NET 10 solution
├── Directory.Build.props             # Shared .NET 10 compiler & nullable/warning rules
├── src/
│   ├── gateways/
│   │   └── api-gateway/              # .NET 10 + YARP Reverse Proxy Gateway
│   ├── services/
│   │   ├── catalog/                  # Java 21 + Spring Boot 3.4 Catalog Service (port 8081)
│   │   ├── inventory/                # Java 21 + Spring Boot 3.4 Inventory Service (port 8082)
│   │   ├── order/                    # Java 21 + Spring Boot 3.4 Order Service (port 8083)
│   │   ├── payment/                  # Java 21 + Spring Boot 3.4 Payment Service (port 8084)
│   │   ├── customer/                 # .NET 10 Customer & Identity Service
│   │   ├── promotion/                # .NET 10 Promotion & Flash Sale Service
│   │   └── notification/             # .NET 10 Notification Service
│   ├── workers/
│   │   └── ai-worker/                # Python 3.12+ FastAPI AI Shopping & Ops Worker
│   └── building-blocks/
│       ├── java/                     # Shared Java 21 cross-cutting module (commerce-building-blocks)
│       ├── dotnet/                   # Shared .NET 10 cross-cutting library (Commerce.BuildingBlocks)
│       └── python/                   # Shared Python 3.12+ cross-cutting package (commerce-common)
├── tests/
│   ├── architecture/                 # Automated boundary & structure tests
│   ├── integration/                  # Testcontainers DB/Redis/Kafka suites (M1+)
│   ├── contract/                     # OpenAPI 3.1 & JSON Schema contract suites (M1+)
│   ├── performance/                  # k6 load & Flash Sale benchmark scripts (M10)
│   └── security/                     # OIDC/JWT & DB privilege verification suites (M1+)
├── deploy/
│   ├── local/                        # Docker Compose & multi-DB initialization (M1)
│   ├── kubernetes/                   # K3s / kubeadm portable Kubernetes manifests
│   └── observability/                # OpenTelemetry, Prometheus, Grafana, Loki, Tempo
└── scripts/
    └── verify-foundation.sh          # One-command build & test verification across Java/.NET/Python
```

---

## 3. Build, Test, and Lint Commands

### 3.1 Run All Polyglot Builds & Unit Tests at Once
```bash
./scripts/verify-foundation.sh
```

### 3.2 Java 21 + Spring Boot 3.4 (`catalog`, `inventory`, `order`, `payment`, `commerce-building-blocks`, `architecture-tests`)
From the repository root:
```bash
# Compile and run all unit & Spring Boot smoke tests
mvn -B test

# Build a single service module (e.g., order-service)
mvn -B test -pl src/building-blocks/java,src/services/order

# Run a service locally
mvn -pl src/services/catalog spring-boot:run
```
- **Health Probes**:
  - Liveness: `GET http://localhost:8081/actuator/health/liveness`
  - Readiness: `GET http://localhost:8081/actuator/health/readiness`
  - OpenAPI UI: `GET http://localhost:8081/swagger-ui.html`

### 3.3 .NET 10 (`api-gateway`, `customer`, `promotion`, `notification`, `Commerce.BuildingBlocks`)
From the repository root:
```bash
# Restore, build, and execute xUnit tests
dotnet test DistributedCommerce.sln

# Run a .NET 10 service locally
dotnet run --project src/gateways/api-gateway/Commerce.ApiGateway
```
- **Health Probes**:
  - Liveness: `GET /health/live`
  - Readiness: `GET /health/ready`
  - OpenAPI JSON: `GET /openapi/v1.json`

### 3.4 Python 3.12+ (`ai-worker` & `commerce-common`)
From `src/workers/ai-worker`:
```bash
cd src/workers/ai-worker

# Run pytest suite using Python 3.12 via uv
uv run --python 3.12 --extra dev pytest

# Run ruff linter & mypy type-checking
uv run --python 3.12 --extra dev ruff check . ../../building-blocks/python
uv run --python 3.12 --extra dev mypy src ../../building-blocks/python/src

# Start the FastAPI worker locally
uv run --python 3.12 uvicorn ai_worker.main:app --reload --port 8090
```
- **Health Probes**:
  - Liveness: `GET http://localhost:8090/health/live`
  - Readiness: `GET http://localhost:8090/health/ready`

---

## 4. Cross-Cutting Engineering Conventions (`M0.3` Foundation)

1. **Correlation ID Propagation (`NFR-OBS-001`)**:
   - Every service accepts `X-Correlation-Id` (or generates a UUID v4 if absent), binds it to structured logs (`correlation_id`), and echoes `X-Correlation-Id` on the HTTP response.
2. **RFC 9457 `ProblemDetails` Error Contract (`NFR-OBS-002`)**:
   - All `4xx`/`5xx` HTTP errors return `application/problem+json` enriched with `correlationId` and `timestamp`.
3. **Fail-Closed Chaos Fault Injection Guard (`CH-07`, `NFR-SEC-004`)**:
   - Every Java, .NET, and Python service executes `FaultInjectionStartupGuard` at startup. If `ENVIRONMENT=production` (or `PRODUCTION_LOCK=true`) is combined with `FAULT_INJECTION_ENABLED=true`, the process aborts startup immediately (`fail-closed`).
4. **Database-per-Service Isolation (`NFR-GOV-001`)**:
   - Services never share tables or connect to another service's database. Cross-service workflows use versioned REST/gRPC contracts or Kafka domain events via the Transactional Outbox (`CH-04`).
