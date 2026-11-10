# Master Technical Specification (`SPEC.md`) — Distributed Commerce & Flash Sale Platform

- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Organization:** [dev-atlas-lab](https://github.com/dev-atlas-lab)
- **Milestone:** `M0 — Product Discovery & Architecture`
- **Status:** `PROPOSED` (Awaiting Human Architect Review & Approval)
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
│   │   └── ADR-0010-event-contracts-json-schema-and-kafka-kraft.md
│   ├── security/
│   │   └── SECURITY_ARCHITECTURE.md
│   ├── performance/
│   │   └── PERFORMANCE_STRATEGY.md
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

## 4. Open Questions Requiring Human Architect Decision (`M0 Gate`)

Before we mark `M0` as `ACCEPTED` and begin `M1`, please review and decide on the following **7 architectural questions**:

1. **Q1 — Repository Location & Git Initialization**:
   - I created the M0 documentation tree at `/home/anhltn/projects/distributed-commerce-platform/` to match your existing `/home/anhltn/projects/` workspace layout (`backend-visual-lab`, `footlab`). Confirm whether you want me to run `git init -b main` in `/home/anhltn/projects/distributed-commerce-platform/`, or if you will clone `dev-atlas-lab/distributed-commerce-platform` yourself first.
2. **Q2 — Target On-Prem Linux VM Hardware Inventory**:
   - The current workspace VM (`vm-anhltn-agy`) is an **ARM64 (`aarch64`) Ubuntu 22.04 VM with 2 vCPUs and 3.8 GiB RAM**.
   - What are the hardware specs (count of VMs, vCPUs, RAM, disk size, and CPU architecture `x86_64` vs `aarch64`) of the Linux VMs you plan to use for local development (`M1–M5`) and the on-prem Kubernetes cluster (`M6–M7`)?
3. **Q3 — Kubernetes Distribution Choice (`K3s` vs. `kubeadm` — `ADR-0009`)**:
   - Do you approve our recommendation of **`K3s` (with bundled Traefik/ServiceLB disabled so we deploy production `MetalLB` + `Ingress-NGINX` + `Calico/Canal`)** to save `~1.2 GiB` control-plane RAM, OR do you want **`kubeadm`** for full manual control-plane/PKI/etcd administration?
4. **Q4 — Flash Sale Unpaid Expiration Stock Policy (`Proposal P-REQ-03`)**:
   - When a Flash Sale winner fails to complete payment within the `10-minute` reservation window, should the released unit:
     - **(Option A — Recommended)**: Automatically return to the live Redis Flash Sale stock counter if the campaign is still within its active time window (and return to standard warehouse `available_qty` if the campaign has ended)?
     - **(Option B)**: Be held back from the live Redis counter and released in scheduled "Second-Chance Wave" drops (or reconciled back to standard inventory at campaign end)?
5. **Q5 — Identity Provider Path (`ADR-0006`)**:
   - Do you approve implementing **`RS256` JWT + `/.well-known/jwks.json` directly inside `Customer Service`** for `M2–M5` (zero extra container overhead, full hands-on auth implementation, 100% OIDC-compatible with Keycloak later), or do you want a **`Keycloak`** container deployed immediately in `M2`?
6. **Q6 — Product Search Engine Path (`ADR-0007`)**:
   - Do you approve starting with **PostgreSQL 17 Full-Text Search (`tsvector` + `pg_trgm` + `JSONB` GIN)** behind a clean `ProductSearchRepository` port in `M2–M4` (saving `~2 GiB` RAM), and benchmarking whether **OpenSearch** is needed in `M4/M7`?
7. **Q7 — LLM Provider for `M5` (`ai-agent-service`)**:
   - Which primary LLM endpoint do you plan to use when we reach `M5` (e.g., `OpenAI API`, `Google Gemini API`, `Anthropic API`, or a self-hosted `Ollama`/`vLLM` model on a GPU host), so we can size the embedding vector dimension (`768` vs `1536`) in `ai_agent_db` accordingly?
