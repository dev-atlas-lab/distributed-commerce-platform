# Master Technical Specification (`SPEC.md`) — Distributed Commerce & Flash Sale Platform

- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Organization:** [dev-atlas-lab](https://github.com/dev-atlas-lab)
- **Milestone:** `M0.2 — Architecture Challenge Refinement (CH-01 to CH-07)`
- **Status:** `ACCEPTED` (Core Decisions `Q1–Q7` Accepted; Refined `CH-01`–`CH-07` Specifications in `PROPOSED` / `DISCUSSION` for Final Gate)
- **Last Updated:** 2026-11-10

---

## 1. Executive Architecture Summary

**Distributed Commerce & Flash Sale Platform** is a polyglot, event-driven microservices system engineered to handle both daily e-commerce transactions and extreme-concurrency **Flash Sale spikes** (`100,000` users competing for `1,000` units), complemented by a zero-privilege **Agentic AI Shopping & Operations Assistant** and deployed onto an **on-prem multi-VM Kubernetes cluster**.

### Key Architectural Pillars
1. **Polyglot Domain Alignment (`ADR-0001`)**:
   - **`.NET 10 LTS`**: `api-gateway` (`YARP`), `customer-service` (OIDC/JWT auth, profile, Redis cart), `promotion-service` (coupons & Flash Sale Redis Lua atomic gate), `notification-service` (async Kafka worker with retry & DLQ).
   - **`Java 21 LTS + Spring Boot 3.4+`**: `product-service` (catalog, MinIO media, PG 17 FTS search), `order-service` (order lifecycle & Saga orchestrator), `inventory-service` (double-entry stock ledger & reservations), `payment-service` (payment simulator, signed webhooks, refunds & reconciliation).
   - **`Python 3.12+ + FastAPI`**: `ai-agent-service` (Shopping & Operations Assistants, `pgvector` RAG, JWT-bound tool calling, Human-in-the-Loop approvals, guardrails).
   - **`React 19 + TypeScript + Vite`**: Customer Storefront SPA & Merchant/Operations Admin Portal SPA.
2. **Strict Data Isolation on Pragmatic Infrastructure (`ADR-0002`)**:
   - Strict **Database-per-Service** ownership (`product_db`, `customer_db`, `order_db`, `inventory_db`, `payment_db`, `promotion_db`, `ai_agent_db`) enforced via separate PostgreSQL database roles with zero cross-database permissions, consolidated onto a single PostgreSQL 17 instance in dev/small-cluster environments to save `>1.5 GiB` RAM.
3. **Verifiable Distributed Consistency (`ADR-0003`, `ADR-0004`, `ADR-0005`)**:
   - **Transactional Outbox + Idempotent Consumer Inbox** over Apache Kafka 3.8 (`KRaft` mode) providing effectively-once state mutations over at-least-once messaging.
   - **Hybrid Order Fulfillment Saga**: Orchestration in `order-service` for core checkout (`Stock + Coupon + Payment + Late-Payment Auto-Refund`) paired with Choreography for downstream notifications and read-model updates.
   - **3-Tier Concurrency Control**: Redis Atomic Lua script (`EVALSHA`) + Kafka queue-leveling for Flash Sales; single-statement conditional atomic SQL (`UPDATE ... WHERE available_qty >= :qty`) with deterministic `sku_id` ordering for standard inventory; `@Version` optimistic locking for low-contention aggregates.
4. **Defense-in-Depth Security (`ADR-0006`, `ADR-0008`)**:
   - Asymmetric `RS256` JWTs with `/.well-known/jwks.json` verification, edge rate limiting, RFC 9457 `ProblemDetails`, and a zero-privilege AI Agent boundary that never touches service databases or trusts LLM-supplied user IDs.

---

## 2. Repository Structure

```text
distributed-commerce-platform/
├── AGENTS.md
├── PROJECT_CONSTITUTION.md
├── README.md
├── SPEC.md
├── ENGINEERING_ROADMAP.md
├── BACKLOG.md
├── docs/
│   ├── product/
│   │   └── PRODUCT_REQUIREMENTS.md
│   ├── domain/
│   │   └── DOMAIN_MODEL.md
│   ├── architecture/
│   │   ├── SYSTEM_ARCHITECTURE.md
│   │   ├── SERVICE_BOUNDARIES.md
│   │   ├── DATA_ARCHITECTURE.md
│   │   ├── EVENT_DRIVEN_ARCHITECTURE.md
│   │   ├── AI_AGENT_ARCHITECTURE.md
│   │   ├── DEPLOYMENT_ARCHITECTURE.md
│   │   └── TEST_STRATEGY.md
│   ├── api-contracts/
│   │   ├── README.md
│   │   └── order-and-flashsale.v1.openapi.yaml
│   ├── event-contracts/
│   │   └── event-envelope.v1.schema.json
│   ├── adr/
│   │   ├── README.md
│   │   ├── ADR-0001-polyglot-microservices-and-service-boundaries.md
│   │   ├── ADR-0002-database-per-service-on-shared-postgres-instance.md
│   │   ├── ADR-0003-transactional-outbox-and-inbox-idempotency.md
│   │   ├── ADR-0004-hybrid-order-fulfillment-saga-orchestration.md
│   │   ├── ADR-0005-flash-sale-concurrency-and-three-tier-locking.md
│   │   ├── ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md
│   │   ├── ADR-0007-catalog-search-postgresql-fts-vs-opensearch.md
│   │   ├── ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md
│   │   ├── ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md
│   │   ├── ADR-0010-event-contracts-json-schema-and-kafka-kraft.md
│   │   └── ADR-0011-observability-opentelemetry-and-lgtm-stack.md
│   ├── infrastructure/
│   │   └── INFRASTRUCTURE_AND_KUBERNETES_STRATEGY.md
│   ├── roadmap/
│   │   └── MILESTONE_ROADMAP.md
│   ├── security/
│   │   └── SECURITY_ARCHITECTURE.md
│   ├── performance/
│   │   └── PERFORMANCE_STRATEGY.md
│   ├── reports/
│   │   └── REPOSITORY_BOOTSTRAP_REPORT.md
│   ├── runbooks/
│   └── engineering-case-studies/
├── frontend/                     # (Scaffolded in M1) React 19 + TS Storefront & Admin UI
├── services/
│   ├── java/                     # (Scaffolded in M1) Product, Order, Inventory, Payment
│   ├── dotnet/                   # (Scaffolded in M1) Gateway, Customer, Promotion, Notification
│   └── python/                   # (Scaffolded in M1) AI Agent Service
├── infrastructure/               # (Scaffolded in M1/M6) Postgres, Redis, Kafka, K8s, Helm, ArgoCD, OTel
├── tests/                        # (Scaffolded in M1–M7) Contract, E2E, Performance (k6), Chaos, Security
├── scripts/                      # (Scaffolded in M1) Toolchain setup, infra verification, CI runner
└── .agents/                      # Antigravity workspace rules, workflows & templates
```

---

## 3. Technology Decision Matrix

| Layer / Capability | Selected Technology | Why Selected | Alternatives Considered & Deferred/Rejected |
| :--- | :--- | :--- | :--- |
| **Frontend SPA** | `React 19`, `TypeScript 5`, `Vite 6`, `TanStack Query v5`, `Zustand`, `React Router`, `Tailwind CSS` | Fast build/HMR, built-in async cache/retry state management (`TanStack Query`), lightweight global stores (`Zustand`), zero heavy runtime overhead. | Next.js SSR (adds Node server deployment complexity not needed for SPA + API Gateway topology), Redux Toolkit (excessive boilerplate). |
| **API Gateway** | `.NET 10` + `YARP` + `Redis RateLimiting` | Native high-performance C# reverse proxy, unified middleware for JWT validation, rate limiting, and `X-Correlation-Id` injection (`ADR-0006`). | Kong, Envoy, Spring Cloud Gateway. |
| **Java Microservices** | `Java 21 LTS` (Virtual Threads), `Spring Boot 3.4+`, `Spring Data JPA`, `Flyway`, `Resilience4j` | Industry standard for high-reliability transactional domains; Virtual Threads provide high concurrency on blocking JDBC/HTTP calls with simple debugging. | Quarkus/Micronaut, Reactive WebFlux (harder stack traces and debugging than Java 21 Virtual Threads). |
| **.NET Microservices** | `.NET 10 LTS`, `ASP.NET Core`, `EF Core`, `MediatR` (where appropriate), `FluentValidation`, `StackExchange.Redis` | Low memory footprint, superlative throughput for `api-gateway` and `promotion-service` Flash Sale hot path. | MassTransit (evaluated; we build explicit Outbox/Inbox to master internals rather than hiding them behind a black-box bus). |
| **Python AI Service** | `Python 3.12+`, `FastAPI`, `Pydantic v2`, `AsyncIO`, `SQLAlchemy Async`, `pgvector`, `OpenTelemetry` | First-class async streaming (`SSE`), strict schema validation for LLM tool calls, vendor-agnostic LLM client abstraction (`ADR-0008`). | Django (too monolithic/sync-oriented), direct LangChain chains without state-machine bounds. |
| **Primary Databases** | `PostgreSQL 17` (7 isolated databases + `pgvector` + `FTS`/`pg_trgm`) | ACID reliability, partial indexes (`WHERE processed_at IS NULL`), `FOR UPDATE SKIP LOCKED`, native JSONB, FTS, and vector embeddings in one engine (`ADR-0002`, `ADR-0007`, `ADR-0008`). | MySQL (lacks partial indexes & `pgvector`), separate OpenSearch + Milvus containers in M1 (consumes `>3 GiB` extra RAM). |
| **In-Memory Cache & Fast Gate** | `Redis 7.4` | Atomic single-threaded Lua execution (`EVALSHA`) for Flash Sale stock/buyer gate, distributed rate limiting, shopping cart storage, and catalog cache-aside (`ADR-0005`). | Memcached (no Lua scripts or rich data structures). |
| **Event Streaming** | `Apache Kafka 3.8+` (`KRaft` mode) | High-throughput partitioned log, durable replay, consumer group scaling, and non-blocking retry/DLQ pipelines without ZooKeeper (`ADR-0010`). | RabbitMQ (lacks long-term partitioned log replay for multiple independent consumers). |
| **Object Storage** | `MinIO` (S3-compatible) | Self-hosted S3 API for pre-signed product image uploads on local and on-prem Kubernetes. | Storing binary blobs in PostgreSQL `BYTEA` (bloats DB backups and buffer cache). |
| **On-Prem Kubernetes** | `K3s` (or `kubeadm`) + `MetalLB` + `Ingress-NGINX` + `Helm` + `Argo CD` | Full CNCF Kubernetes compliance with low control-plane memory overhead (`ADR-0009`). | Managed EKS/GKE (out of scope for on-prem VM goal). |
| **Observability & Load Testing** | `OpenTelemetry`, `Prometheus`, `Grafana`, `Loki`, `Tempo`, `k6` | Vendor-neutral telemetry correlation (`trace_id` across logs, metrics, and traces) and scriptable Go/JS load generation (`k6`). | JMeter (heavy XML/thread overhead compared to `k6`). |

---

## 4. Approved Architecture Decisions (`M0.1 — ACCEPTED`) & Phase 4 Deep Challenges (`PROPOSED`)

All 7 foundational decisions (`Q1–Q7`) have been reviewed and **approved (`Status: ACCEPTED`)** by the Human Architect:
1. **Q1 (`ACCEPTED`)**: GitHub repository `dev-atlas-lab/distributed-commerce-platform` created, connected to `/home/anhltn/projects/distributed-commerce-platform/`, and synced on `main`.
2. **Q2 (`ACCEPTED` — [`ADR-0009`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md))**: 3–4 additional Linux VMs (`2 vCPUs`, `~3.8 GiB RAM`) can be provisioned alongside the current VM (`4–5 VMs` total cluster topology).
3. **Q3 (`ACCEPTED` — [`ADR-0009`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md))**: Start with **`K3s`** (`--disable traefik --disable servicelb` + standard `MetalLB` + `Ingress-NGINX`) and maintain 100% manifest portability for a later migration to **`kubeadm`**.
4. **Q4 (`ACCEPTED` — [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md))**: **Option A** — Expired Flash Sale reservations return stock to the active Redis campaign pool if the campaign is still `ACTIVE`, protected by idempotency and reconciliation safeguards.
5. **Q5 (`ACCEPTED` — [`ADR-0006`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md))**: Design standards-compliant **OIDC Discovery (`/.well-known/openid-configuration`, `/.well-known/jwks.json`) + `RS256` JWT** from the beginning in `customer-service`, ready for seamless **Keycloak** introduction later.
6. **Q6 (`ACCEPTED` — [`ADR-0007`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0007-catalog-search-postgresql-fts-vs-opensearch.md))**: Start with **PostgreSQL 17 Full-Text Search (`tsvector` + `pg_trgm` + `JSONB` GIN)** and benchmark with `k6` before considering **OpenSearch**.
7. **Q7 (`ACCEPTED` — [`ADR-0008`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md))**: Use a **Multi-Provider AI Abstraction Port** supporting **OpenAI**, **Google Gemini**, and **Anthropic Claude** behind a zero-privilege API-only tool boundary.

### Pending `M0.2` Deep Architecture Challenge Refinements (`Status: PROPOSED`)
See [`docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md) for the 7 comprehensive `M0.2` engineering specifications (`CH-01` through `CH-07`) awaiting your explicit approval (`Q-CH01` through `Q-CH07`) before we start `M1`:
- **`CH-01` (`Q-CH01`)**: Flash Sale Two-Phase Claim Lease + **PostgreSQL Tombstone Fencing (`ABANDONED_FENCED`) before Redis Restock** (replacing the 30s timeout assumption) + `HSETNX released_claims` at-most-once restock guard.
- **`CH-02` (`Q-CH02`)**: Orthogonal **`Order` State Machine** vs. **`Payment` State Machine** (`Auth -> Capture/Void` + `Direct Capture -> Auto-Refund` on late webhook, replacing the 2s clock buffer) + monotonic webhook state precedence ranks.
- **`CH-03` (`Q-CH03`)**: **Two-Class Idempotency Protocol** (`Class A` single-TX atomic vs. `Class B` checkpointed state machine preserving `downstream_operation_id` across `UNKNOWN_RETRYABLE` timeouts—never deleting records on `5xx` after external side effects) + RFC 8785 canonical `SHA-256` payload hashing.
- **`CH-04` (`Q-CH04`)**: Mandatory `aggregateVersion` + `outbox_sequence` ordering, explicit ordering boundary matrix, **Terminal Tombstones** for out-of-order cancellations, and state-guarded DLQ replay.
- **`CH-05` (`Q-CH05`)**: RFC 9068 OIDC token profile, split `AUTH_ISSUER_URI` (logical claim) vs. `AUTH_JWKS_URI` (internal fetch), dual-key JWKS rotation (`ACTIVE_SIGNER` + `VERIFY_ONLY`), and least-privilege scoped `client_credentials` M2M identity.
- **`CH-06` (`Q-CH06`)**: Generation-isolated **`embedding_index_generations` + `chunk_embeddings`** schema supporting arbitrary model dimensions (`384`, `768`, `1024`, `1536`, `3072`), strict `(provider, model_name, model_version, dimensions)` vector-space isolation, and Blue/Green zero-downtime re-indexing.
- **`CH-07` (`Q-CH07`)**: OpenTelemetry per-message `traceparent` restoration across Outbox/Inbox + **SpanLink** to batch poller, W3C `baggage` PII allowlist, and dual-gated (`DI registration + ADMIN_OPS chaos:inject scope`) fault injection.
