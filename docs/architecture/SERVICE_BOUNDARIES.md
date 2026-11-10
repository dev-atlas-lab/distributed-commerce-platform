# Service Boundaries & Responsibility Matrix — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-ARCH-002`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Critical Evaluation of Proposed Service Boundaries

The mission brief proposes **9 deployable services** across `.NET 10`, `Java 21`, and `Python 3.12+`. Before adopting them, our engineering philosophy requires asking:

> *"Does each service deserve independent deployment, and how do we survive its operational footprint on constrained development/on-prem VM hardware?"*

### 1.1 Service Justification & Independent Deployment Analysis

| # | Service | Stack | Independent Deployment Justification | Scaling & Resource Profile | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **`api-gateway`** | `.NET 10` (`YARP`) | Edge routing, JWT validation, per-user/IP rate limiting, request correlation, and CORS termination must scale and update independently of backend business logic. | Stateless, CPU/network bound, low memory (`~128–256 MiB`). | **KEEP** |
| 2 | **`product-service`** | `Java 21` (`Spring Boot 3`) | Read-heavy catalog browsing (`90%+` of regular traffic) with distinct caching and search indexing lifecycles from transactional order/stock mutations. | Read-intensive, benefits from Redis cache-aside and read replicas (`~384–512 MiB`). | **KEEP** |
| 3 | **`customer-service`** | `.NET 10` (`ASP.NET Core`) | Owns identity/profile, shipping addresses, and ephemeral Redis shopping cart. Isolates PII data and authentication flows from catalog/order services. | Low-to-moderate write load, high auth/cart read frequency (`~192–256 MiB`). | **KEEP** |
| 4 | **`order-service`** | `Java 21` (`Spring Boot 3`) | Owns the `Order` lifecycle and coordinates the **Order Fulfillment Saga**. High write contention during checkout bursts; requires strict transactional outbox isolation. | Write-heavy transactional coordinator (`~384–512 MiB`). | **KEEP** |
| 5 | **`inventory-service`** | `Java 21` (`Spring Boot 3`) | Single source of truth for physical/reservable SKU quantities and `inventory_ledger`. Isolates row-level lock contention (`StockItem`) from order/catalog queries. | High lock contention on hot SKUs (`~384–512 MiB`). | **KEEP** |
| 6 | **`payment-service`** | `Java 21` (`Spring Boot 3`) | Isolates external payment gateway simulation, webhook idempotency, timeout sweeps, and financial reconciliation from core order state. | I/O bound waiting on payment callbacks; strict audit requirements (`~384–512 MiB`). | **KEEP** |
| 7 | **`promotion-service`** | `.NET 10` (`ASP.NET Core`) | Owns coupon rules AND **Flash Sale Campaign orchestration + Redis Lua fast gate**. Allows independent horizontal scaling during a 100K-user Flash Sale spike without scaling catalog or notification pods. | Extreme burst RPS during Flash Sale (`~256–384 MiB`). | **KEEP** |
| 8 | **`notification-service`** | `.NET 10` (`Worker / API`) | Purely asynchronous event consumer (`Kafka` → `SMTP/In-App`) with slow external I/O, retry topics, and DLQ. Must never block or share thread pools with synchronous checkout APIs. | Async background consumer (`~150–256 MiB`). | **KEEP** |
| 9 | **`ai-agent-service`** | `Python 3.12+` (`FastAPI`) | LLM orchestration, RAG retrieval (`pgvector`), streaming SSE responses, and guardrails rely on the Python AI ecosystem and exhibit long-lived connections (`2–15s`). | Long-lived async I/O (`~256–512 MiB`). | **KEEP** |

---

## 2. Architectural Challenge: The Memory Footprint Reality Check

> [!WARNING]
> **Hardware Constraint Challenge**: Our environment inspection (`Step 1`) revealed that the current workspace VM (`vm-anhltn-agy`) has **2 ARM64 vCPUs and 3.8 GiB RAM (0 B Swap)**. Running 4 JVM microservices + 4 .NET microservices + 1 Python service + PostgreSQL + Kafka + Redis + Frontend + Observability simultaneously on a single 3.8 GiB VM without profile slicing **will trigger Linux OOM-Killer**.

### Mitigation Strategy: Layered Docker Compose Profiles & Multi-VM K8s Sizing
To keep all 9 service boundaries clean while respecting physical RAM limits:
1. **Single PostgreSQL Server with Isolated Per-Service Databases in Dev/Small Lab**: Instead of running 7 separate PostgreSQL container processes (`7 × 250 MiB`), run **1 PostgreSQL 17 instance** hosting **7 strictly isolated databases (`product_db`, `customer_db`, `order_db`, `inventory_db`, `payment_db`, `promotion_db`, `ai_agent_db`)**, each with its own dedicated PostgreSQL role (`product_user`, `order_user`, etc.) with **zero cross-database permissions**. This enforces strict Database-per-Service isolation at near-zero memory overhead.
2. **Composable Docker Compose Profiles (`M1`)**:
   - `profile: infra` — Postgres 17, Redis 7.4, Kafka 3.8 (KRaft single-node without ZooKeeper).
   - `profile: core-commerce` — Gateway, Product, Customer, Order, Inventory (`M2–M3`).
   - `profile: flash-sale` — Adds Promotion, Payment, Notification (`M4`).
   - `profile: ai` — Adds Python AI Agent (`M5`).
   - `profile: observability` — Adds OpenTelemetry Collector, Prometheus, Grafana, Loki, Tempo (`M6`).
3. **JVM & .NET Container Memory Tuning**:
   - Java 21 services in dev/constrained nodes use `-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC` (or `G1GC` on larger nodes) with container limits of `384Mi–512Mi` and Virtual Threads (`spring.threads.virtual.enabled=true`).
   - .NET 10 services use `DOTNET_GCHeapHardLimit` and Server/Workstation GC tuned per container limit (`192Mi–256Mi`).

---

## 3. Service Responsibility Matrix (RACI / Ownership)

| Business Capability / Data Entity | Owning Service (Write Authority) | Read / Query Consumers | Integration Mechanism |
| :--- | :--- | :--- | :--- |
| **Edge Routing, Rate Limiting, JWT Validation** | `api-gateway` (`.NET`) | All external clients (React Storefront, Admin UI) | Sync HTTP/HTTPS Reverse Proxy (`YARP`) |
| **Categories, Products (SPU), Variants (SKU), Base Prices, Media URLs** | `product-service` (`Java`) | Storefront, Admin UI, `order-service` (price snapshot validation), `ai-agent-service` | Sync REST (`GET /api/v1/products/**`) + Kafka `catalog.product.events.v1` |
| **Customer Accounts, Auth Credentials, Addresses, Shopping Cart** | `customer-service` (`.NET`) | Storefront, Admin UI, `order-service` (address validation) | Sync REST (`GET/POST /api/v1/customers/**`, `/api/v1/cart/**`) |
| **Physical Stock, Available/Reserved Counts, Inventory Ledger** | `inventory-service` (`Java`) | Storefront, Admin UI, `order-service`, `promotion-service`, `ai-agent-service` | Sync REST (`GET /api/v1/inventory/**`) + Kafka `inventory.stock.events.v1` |
| **Order Lifecycle, Order Lines, Order Fulfillment Saga State** | `order-service` (`Java`) | Storefront, Admin UI, `ai-agent-service` | Sync REST (`POST/GET /api/v1/orders/**`) + Kafka `commerce.order.events.v1` |
| **Payment Intents, Simulator Webhooks, Refunds, Reconciliation** | `payment-service` (`Java`) | Storefront, Admin UI, `order-service`, `ai-agent-service` | Sync REST (`POST /api/v1/payments/**`) + Kafka `commerce.payment.events.v1` |
| **Coupons, Discount Rules, Flash Sale Campaigns & Redis Lua Gate** | `promotion-service` (`.NET`) | Storefront, Admin UI, `order-service`, `ai-agent-service` | Sync REST (`/api/v1/promotions/**`, `/api/v1/flash-sales/**`) + Kafka `commerce.flashsale.events.v1` |
| **Email & In-App Notification Dispatch, Retry & DLQ** | `notification-service` (`.NET`) | Admin UI (delivery logs) | Async Kafka Consumer (`order`, `payment`, `flashsale` events) |
| **Conversational Shopping Assistant, Ops Analytics Assistant, RAG Embeddings** | `ai-agent-service` (`Python`) | Storefront Chat Drawer, Admin Ops Console | Sync REST / SSE (`/api/v1/ai/chat/**`) → Calls backend APIs as authorized client |

---

## 4. Forbidden Cross-Service Anti-Patterns

1. **No Cross-Database Queries or Foreign Keys**: `order-service` must never SQL-join `order_db.orders` with `product_db.product_variants` or `inventory_db.stock_items`.
2. **No Synchronous Long Chains (`Depth > 2`)**: A client call to `POST /api/v1/orders` may perform at most 1 fast synchronous validation read (or price/address snapshot fetch with local cache + circuit breaker) before persisting `Order(PENDING_RESERVATION)` and driving stock reservation, coupon lock, and payment via the **Asynchronous Kafka Saga**.
3. **No Shared Domain Libraries Containing Entities**: Services in the monorepo may share observability/logging conventions or OpenAPI/JSON Schema contract files (`docs/api-contracts/`, `docs/event-contracts/`), but must NEVER share JPA/@Entity or EF Core `DbContext` model classes across service boundaries.
4. **No Uniform Internal Architecture Dogma**:
   - Complex domain/saga services (`order-service`, `inventory-service`, `payment-service`, `promotion-service`) use **Pragmatic Clean / Hexagonal Architecture** (`domain`, `application`, `infrastructure`, `presentation`).
   - Simpler data/event services (`notification-service`, `customer-service`) may use **Vertical Slice Architecture** or lightweight layered structure where full DDD aggregates add unnecessary ceremony.
