# Comprehensive Test Strategy — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-TST-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Testing Philosophy & Mandatory Rules

1. **Every Business Feature Requires 3 Test Categories**:
   - **Positive Tests**: Valid inputs, standard happy-path workflows.
   - **Negative Tests**: Invalid inputs (`400`), unauthenticated (`401`), unauthorized/IDOR (`403`/`404`), insufficient stock/expired coupon (`409`), missing upstream dependencies (`503`).
   - **Edge-Case & Concurrency Tests**: Boundary values (`quantity = 0`, `stock = 1` with `50` concurrent buyers), duplicate `Idempotency-Key` replay, duplicate Kafka event delivery, late webhook arrival after order expiration.
2. **Real Infrastructure over Fragile Mocks for Integration Tests**:
   - Never mock `JdbcTemplate`, `EntityManager`, `DbContext`, Redis Lua execution, or Kafka serialization in integration tests. Use **Testcontainers** (`PostgreSQL 17`, `Redis 7.4`, `Apache Kafka KRaft`) so SQL constraints, lock contention, Flyway/EF migrations, and Lua scripts are verified against real engines.
3. **Zero Tolerance for Flaky or Weakened Tests**:
   - Never use `@Disabled` / `[Fact(Skip=...)]`, `Thread.sleep()` polling hacks (use `Awaitility`), or weakened assertions just to turn CI green.

---

## 2. Multi-Layer Verification Matrix

| Test Layer | Scope & Purpose | Tools (Java / .NET / Python / React) | Execution Speed | Trigger |
| :--- | :--- | :--- | :--- | :--- |
| **1. Architecture Tests** | Enforce Clean Architecture layer boundaries (zero infra imports in `domain`). | `ArchUnit` (Java), `NetArchTest` (.NET), `import-linter` (Python) | `< 5s` | Every build / PR |
| **2. Domain Unit Tests** | Pure in-memory aggregate invariants, state transitions, value object math. | `JUnit 5 + AssertJ`, `xUnit + FluentAssertions`, `pytest`, `Vitest` | `< 10s` | Every commit |
| **3. Component / Slice Tests** | REST controller validation (`ProblemDetails`), UI component states (`loading`, `empty`, `error`, `retry`). | `@WebMvcTest`, `WebApplicationFactory`, `FastAPI TestClient`, `Vitest + React Testing Library` | `< 30s` | Every PR |
| **4. Integration & Concurrency Tests** | Real DB transactions, Outbox/Inbox idempotency, parallel thread barrier tests (`CountDownLatch`), Redis Lua atomicity. | `Testcontainers` (`Postgres`, `Redis`, `Kafka`) across Java, .NET, Python | `1–3m` | Every PR |
| **5. Contract Tests** | Validate REST payloads against `docs/api-contracts/*.openapi.yaml` and Kafka events against `docs/event-contracts/*.schema.json`. | `openapi4j` / `Schemathesis`, `networknt/json-schema-validator`, `JsonSchema.Net`, `jsonschema` | `< 20s` | Every PR |
| **6. End-to-End (E2E) & Accessibility Tests** | Full user journeys across React Storefront + Admin UI + API Gateway + Backend Services + WCAG checks. | `Playwright` + `@axe-core/playwright` | `2–5m` | Milestone Gate / Nightly |
| **7. Performance & Chaos Tests** | Throughput, `p95`/`p99` latency, zero-oversell under spike, pod/broker failure recovery. | `k6` + Chaos scripts (`tests/performance/`, `tests/chaos/`) | `5–60m` | Milestone M4, M6, M7 |

---

## 3. Signature Concurrency & Distributed Failure Test Cases

Every core domain milestone must pass these deterministic verification scenarios:

1. **`TC-CONC-01` (Standard Stock Contention Barrier)**:
   - Seed SKU with `available_qty = 10`. Launch `100` concurrent threads pinned to a `CyclicBarrier` attempting to reserve `1` unit each.
   - **Assertion**: Exactly `10` reservations succeed (`RESERVED`), `90` fail with `INVENTORY_INSUFFICIENT_STOCK`, final `available_qty == 0`, `reserved_qty == 10`, and `inventory_ledger_entries` count `== 11` (1 initial seed + 10 reservations).
2. **`TC-CONC-02` (Flash Sale Lua Atomic Gate + Per-User Limit)**:
   - Seed Flash Sale SKU with `quota = 50`, `per_user_limit = 1`. Fire `500` concurrent requests (`100` from the same `user_A` and `400` from distinct users).
   - **Assertion**: `user_A` wins at most `1` unit (`99` rejected with `USER_LIMIT_EXCEEDED`), total winners across all users `== 50`, remaining Redis stock `== 0`, `400+` rejected with `SOLD_OUT`.
3. **`TC-IDEMP-01` (Duplicate Checkout Request Replay)**:
   - Fire `10` simultaneous `POST /api/v1/orders` requests with the same `(customer_id, Idempotency-Key)`.
   - **Assertion**: Exactly `1` row created in `orders`, `1` `OrderCreated` outbox message emitted, all `10` HTTP callers receive the same `orderId`.
4. **`TC-IDEMP-02` (Duplicate Kafka Event Delivery)**:
   - Publish the same `eventId` (`OrderCreated` or `PaymentSucceeded`) `5` times to Kafka.
   - **Assertion**: `inbox_messages` deduplicates `4` deliveries; stock/order state mutates only once.
5. **`TC-SAGA-01` (Late Payment After Order Expiry)**:
   - Create order, reserve stock, advance clock past `expires_at`, run expiration worker (`Order -> EXPIRED`, `Stock -> RELEASED`), then deliver `PaymentSucceeded` webhook.
   - **Assertion**: Order transitions to `REFUND_PENDING`, `RefundRequested` event is emitted, and `Payment Service` executes compensating refund.
