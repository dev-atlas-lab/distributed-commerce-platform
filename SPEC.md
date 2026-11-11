# Master Technical Specification (`SPEC.md`) — Distributed Commerce & Flash Sale Platform

- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Organization:** [dev-atlas-lab](https://github.com/dev-atlas-lab)
- **Milestone:** `M0.2.4 — Final Fencing Review (CH-01 & CH-04)`
- **Status:** `ACCEPTED` (Core Decisions `Q1–Q7` Accepted; `CH-01`–`CH-07` Adversarially Verified & Fencing-Hardened in [`M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md), [`M0_2_3_CONCURRENCY_CORRECTIONS.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_3_CONCURRENCY_CORRECTIONS.md), and [`M0_2_4_FINAL_FENCING_REVIEW.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md) — Pending Final Sign-Off)
- **Last Updated:** 2026-11-11

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
├── M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md
├── M0_2_3_CONCURRENCY_CORRECTIONS.md
├── M0_2_4_FINAL_FENCING_REVIEW.md
├── ENGINEERING_ROADMAP.md
├── BACKLOG.md
├── docs/
│   ├── product/
│   │   └── PRODUCT_REQUIREMENTS.md
│   ├── domain/
│   │   └── DOMAIN_MODEL.md
│   ├── architecture/
│   │   ├── ARCHITECTURE_CHALLENGE_M0_1.md
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

### Pending `M0.2.4` Deep Architecture Challenge Sign-Off (`Status: PROPOSED`)
See [`docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md) and [`M0_2_4_FINAL_FENCING_REVIEW.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md) for the `M0.2.4` specifications (`CH-01` through `CH-07`) awaiting your final sign-off before we transition to `M1`:
- **`CH-01` (`PROPOSED` — Finalized in `M0.2.4`)**: Complete 8-path `campaign_guard` CTE `FOR SHARE` / `FOR UPDATE` barrier (`1. flash_sale_campaigns -> 2. flash_sale_claims -> 3. flash_sale_items`) + dual-table `BEFORE INSERT OR UPDATE OR DELETE` triggers, epoch-validated `flash_sale_release.lua`, and strict separation of PostgreSQL `FOR UPDATE` mutual exclusion (correctness) from `3s` session timeouts / `pg_terminate_backend` (liveness).
- **`CH-02` (`PROPOSED` — Verified in `M0.2.2`)**: Explicit **`Order` and `PaymentAttempt` State Transition Matrices** + non-fabricated provider fact timestamps (`provider_authorized_at`, `provider_captured_at`, `provider_voided_at`, `provider_refunded_at`) + `refund_requests` (`UNIQUE (attempt_id, reason_code)`).
- **`CH-03` (`PROPOSED` — Verified in `M0.2.2`)**: Monotonic **`lease_generation` fencing tokens**, immutable `downstream_operation_id`, and **`RECONCILING` state** (distinguishing Type I authoritative `NOT_FOUND` from Type II eventual `NOT_FOUND` -> `MANUAL_INTERVENTION_REQUIRED`).
- **`CH-04` (`PROPOSED` — Finalized in `M0.2.4`)**: **Dedicated Shard Dispatcher (`StatefulSet` ordinal pinning + single thread per shard) + Two-Stage `INITIALIZING -> ACTIVE` Ownership State Machine (`owner_backend_pid`, `15s` pre-init watchdog vs. `35s` `initializing_deadline`, `ACTIVATE_SHARD_CAS` before any `Phase 1` query, self-healing `ProducerFencedException` recovery) + Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)**.
- **`CH-05` (`PROPOSED` — Direction Approved, Final Validation)**: Explicitly separated OIDC `id_token` (`aud: "commerce-web-spa"`, SPA-only) from RFC 9068 OAuth2 `access_token` (`aud: "commerce-api"`, Resource Servers), defined the 5-step Keycloak-compatible claim normalization pipeline (`client_id`/`azp`, `roles`/`realm_access.roles`, `scope`), and established the per-service policy matrix.
- **`CH-06` (`PROPOSED` — Corrected in `M0.2.1`)**: Explicitly distinguished `pgvector` unindexed column limit (`16,000d`) from **HNSW/IVFFlat ANN index ceilings (`2,000d` for FP32 `vector` vs. `4,000d` for FP16 `halfvec`)**, enforced via DB `CHECK` constraint so `3072d` models use `halfvec_cosine_ops` with model-generation isolation.
- **`CH-07` (`PROPOSED` — Direction Approved, Final Validation)**: Enforced zero-trust on W3C `baggage` (never used for auth/identity), restricted fault injection to server-registered `fault.profile_id` lookups (`fault-profiles.yaml`) with target allowlists and mandatory audit logs, and excluded fault injection in production builds.
