# Product Requirements Document (PRD) — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-PRD-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Product Vision & Strategic Purpose

**Distributed Commerce & Flash Sale Platform** is a production-grade e-commerce ecosystem built to handle both standard retail operations and extreme-concurrency **Flash Sale campaigns** (e.g., 100,000 participating users competing for 1,000 high-demand units within seconds), enhanced by an **Agentic AI Shopping & Operations Assistant**.

### 1.1 Dual Value Proposition
1. **Business & User Value**: Customers experience fast product discovery, fair and transparent flash-sale participation, reliable checkout, real-time order tracking, and conversational AI shopping assistance. Merchants/Administrators manage catalog, inventory, promotions, flash-sale allocations, and operational analytics from a unified Admin Portal.
2. **Engineering Proof Value**: Every business workflow is engineered to expose and solve real distributed-system challenges—race conditions, overselling, duplicate requests, split-brain network partitions, slow consumers, payment gateway timeouts, and LLM prompt injection—yielding verifiable artifacts and benchmarks suitable for Senior/Staff Backend & Solution Architect interviews.

---

## 2. Target Personas

| Persona | Role Code | Description & Primary Goals | Key Pain Points Addressed |
| :--- | :--- | :--- | :--- |
| **Retail Shopper** | `CUSTOMER` | Browses catalog, compares products, applies coupons, places standard orders, tracks delivery, and uses the AI Shopping Assistant. | Slow search, confusing coupon rules, opaque order status after payment. |
| **Flash Sale Participant** | `CUSTOMER` | Joins scheduled high-demand campaigns at `T=0`, attempts to claim 1 unit under heavy contention, and completes payment within a strict reservation window (e.g., 10 minutes). | UI freezes at launch, unfair overselling followed by silent cancellation, duplicate charges on retry. |
| **Catalog & Promotion Manager** | `ADMIN_MERCHANT` | Creates products, SKUs, categories, pricing, discount rules, coupon campaigns, and Flash Sale schedules/quotas. | Accidental stock mismatch between standard inventory and flash-sale allocation. |
| **Operations & Support Engineer** | `ADMIN_OPS` | Monitors live Flash Sale traffic, inspects failed payments, reconciles stuck orders, manages DLQ events, and queries the AI Operations Assistant for anomaly root-cause analysis. | Lack of visibility into why orders fail or where inventory reservations are leaking. |

---

## 3. Core User Journeys

### Journey J1: Standard E-Commerce Checkout (Happy Path & Compensation)
1. Customer browses/searches catalog (`Product Service`) and views real-time availability (`Inventory Service`).
2. Customer adds SKU items to Cart, applies a coupon code (`Promotion Service` validates eligibility and calculates discount), and submits Checkout with an `Idempotency-Key`.
3. `Order Service` creates an order in `PENDING_RESERVATION` state and initiates the **Order Fulfillment Saga**:
   - Step 1: Reserve stock in `Inventory Service` + lock coupon usage in `Promotion Service`.
   - Step 2: Initiate payment intent via `Payment Service` (Payment Simulator).
   - Step 3: Customer confirms payment; `Payment Service` emits `PaymentSucceeded` (or `PaymentFailed` / `PaymentTimedOut` after 15m TTL).
   - Step 4: On success, `Order Service` transitions to `CONFIRMED`, `Inventory Service` commits reserved stock to deducted, and `Notification Service` sends order confirmation email.
   - Step 5 (Compensation): On payment failure/timeout or user cancellation, `Inventory Service` releases reserved stock back to available pool, `Promotion Service` releases single-use coupon lock, and `Order Service` transitions to `CANCELLED` or `EXPIRED`.

### Journey J2: High-Concurrency Flash Sale Purchase
1. **Pre-Warming (`T - 15m`)**: Admin approves Flash Sale campaign (`1,000 units` of SKU `IPHONE-16-PRO`, limit `1 per customer`, duration `30m`). Stock is explicitly allocated from Warehouse Available Stock into Flash Sale Reserved Stock and pre-warmed into Redis keys (`flashsale:{campaignId}:sku:{skuId}:stock`, `flashsale:{campaignId}:sku:{skuId}:buyers`).
2. **Traffic Spike (`T = 0s`)**: 100,000 users click "Buy Now" within seconds.
   - Edge/Gateway enforces per-user and per-IP rate limiting.
   - Fast-path atomic Lua script in Redis checks:
     1. Is campaign active (`now` between `start_time` and `end_time`)?
     2. Has `user_id` already claimed (`SISMEMBER` / `HSETNX` buyer set)?
     3. Is remaining stock $\ge$ requested quantity (`DECRBY`)?
   - If rejected (stock $= 0$ or duplicate user): immediately return `409 Conflict` (`FLASH_SALE_SOLD_OUT` or `ALREADY_PARTICIPATED`) in $< 10\text{ ms}$ without hitting PostgreSQL.
   - If accepted: Redis atomically decrements stock, records reservation token, and the service publishes `FlashSaleSlotClaimed` via Outbox/Kafka to asynchronously materialize the `Order` and PostgreSQL `StockReservation` with a 10-minute payment TTL.
3. **Polling / Status Push**: Client receives `202 Accepted` with `reservationToken` and polls/subscribes for order readiness (`READY_FOR_PAYMENT`), then completes payment within 10 minutes.
4. **Expiration & Reconciliation**: If payment times out after 10 minutes, `Order` expires, PostgreSQL reservation is released, and a policy decision determines whether expired Flash Sale stock is returned to the live Redis pool or held for a second-wave drop (see Open Question Q4).

### Journey J3: Conversational AI Shopping Assistant
1. Customer asks: *"Find me a mechanical keyboard under \$150 that is currently in stock and has an active discount code, then compare the top 2 options."*
2. `AI Agent Service` (Python) orchestrates tool calls (`search_products`, `check_inventory`, `get_active_promotions`, `compare_products`) through authenticated backend APIs, retrieves grounded product specifications via RAG, and synthesizes an accurate comparison table without hallucinating prices or stock counts.
3. Customer asks: *"Where is my latest order and why did payment fail?"* — Agent calls `get_order_status` scoped strictly to the authenticated customer's JWT subject (`sub`).

### Journey J4: AI Operations & Anomaly Assistant
1. Admin asks: *"Summarize failed payments in the last hour during the Flash Sale and check if any reserved stock is stuck."*
2. `AI Agent Service` verifies `ADMIN_OPS` role, executes read-only diagnostic tools against Order, Payment, and Inventory operational endpoints, and produces a structured incident summary. Any state-mutating action (e.g., triggering manual reservation release) requires explicit human confirmation (`Human-in-the-Loop` approval token).

---

## 4. Functional Requirements Matrix

| Domain | ID | Requirement Summary | Priority | Target Milestone |
| :--- | :--- | :--- | :--- | :--- |
| **Product Catalog** | `FR-PRD-01` | CRUD for Categories (hierarchical tree), Products (SPU), and Variants (SKU with attributes like color/storage, base price, active status). | P0 | M2 |
| | `FR-PRD-02` | Product image upload and retrieval via pre-signed URLs backed by S3-compatible object storage (`MinIO`). | P1 | M2 |
| | `FR-PRD-03` | Full-text, faceted, and filtered search (by category, price range, attributes, availability, sort order). | P0 (PG FTS) / P1 (Search Engine) | M2 / M4 |
| **Customer & Auth** | `FR-CUS-01` | Customer registration, login, token refresh, password hashing (`Argon2id`/`BCrypt`), and RBAC (`CUSTOMER`, `ADMIN_MERCHANT`, `ADMIN_OPS`). | P0 | M2 |
| | `FR-CUS-02` | Customer profile, multiple shipping addresses (with default flag), and notification preferences. | P0 | M2 |
| **Inventory** | `FR-INV-01` | Track `available_qty`, `reserved_qty`, and `flash_sale_allocated_qty` per SKU with strict non-negative constraint (`available_qty >= 0`). | P0 | M3 |
| | `FR-INV-02` | Idempotent stock reservation (`RESERVE`), commit (`COMMIT`), release (`RELEASE`), and admin stock adjustment with immutable `inventory_ledger` audit history. | P0 | M3 |
| **Order** | `FR-ORD-01` | Create order with client `Idempotency-Key`, immutable price/product snapshot at purchase time, and deterministic state machine lifecycle. | P0 | M2 / M3 |
| | `FR-ORD-02` | Order cancellation (customer-initiated before shipment or system-initiated on timeout/failure) triggering compensating stock/coupon release. | P0 | M3 |
| | `FR-ORD-03` | Paginated order history and detailed order status timeline for customers and admins. | P0 | M2 |
| **Payment** | `FR-PAY-01` | Payment Simulator supporting deterministic test outcomes (`SUCCEED_IMMEDIATELY`, `SUCCEED_DELAYED`, `FAIL_INSUFFICIENT_FUNDS`, `TIMEOUT`, `WEBHOOK_DUPLICATE`). | P0 | M4 |
| | `FR-PAY-02` | Idempotent webhook/callback handling, refund processing, and scheduled reconciliation job for stuck `PENDING` payments. | P0 | M4 |
| **Promotion & Flash Sale** | `FR-PRM-01` | Coupon management (percentage, fixed amount, min order value, usage limit per user & total, validity window) and atomic redemption lock. | P1 | M4 |
| | `FR-PRM-02` | Flash Sale campaign lifecycle (`DRAFT` → `APPROVED` → `WARMED` → `ACTIVE` → `ENDED` → `RECONCILED`), per-user purchase limits, and high-concurrency Redis+Kafka reservation pipeline. | P0 | M4 |
| **Notification** | `FR-NOT-01` | Asynchronous event-driven notifications (Order Created, Payment Confirmed/Failed, Order Cancelled) via SMTP sink (`Mailpit` in dev/staging) with retry & DLQ. | P1 | M3 / M4 |
| **AI Assistant** | `FR-AIA-01` | Customer Shopping Assistant (discovery, comparison, RAG Q&A, live price/stock/promotion/order lookup via tool calling). | P1 | M5 |
| | `FR-AIA-02` | Admin Operations Assistant (sales/order/payment failure analysis, inventory anomaly detection, human-in-the-loop action confirmation). | P1 | M5 |
| **Frontend** | `FR-FE-01` | Responsive React Customer Storefront (Catalog, Product Detail, Flash Sale Live Arena, Cart/Checkout, Order Tracking, AI Chat Drawer). | P0 | M2–M5 |
| | `FR-FE-02` | React Admin Portal (Catalog & SKU Editor, Inventory Ledger, Promotion & Flash Sale Scheduler, Order/Payment Inspector, AI Ops Console). | P0 | M2–M5 |

---

## 5. Non-Functional Requirements (NFRs) & SLOs

> [!IMPORTANT]
> The capacity figures below are **engineering design targets and workload assumptions**, not pre-existing guarantees. All targets must be empirically measured and tuned in **M7 (Performance & Reliability)** on the actual target hardware.

| Category | Metric / Requirement | Target Design Objective | Verification Method |
| :--- | :--- | :--- | :--- |
| **Concurrency & Correctness** | Oversell Tolerance | **0 oversold units** (`available_qty < 0` or `claimed > quota`) under 20,000+ concurrent requests. | `k6` Spike Test + DB invariant assertion query |
| **Idempotency** | Duplicate Order / Double Charge | **0 duplicate orders or payments** when identical requests/webhooks are replayed $10\times$ concurrently. | Parallel idempotency integration & chaos tests |
| **Latency (Read APIs)** | Product Catalog & Search (`GET`) | `p50 < 30ms`, `p95 < 100ms`, `p99 < 250ms` at 500 RPS | `k6` Load Test + Prometheus histogram |
| **Latency (Standard Checkout)** | Order Placement (`POST /orders`) | `p50 < 80ms`, `p95 < 250ms`, `p99 < 500ms` (async Saga initiation) | `k6` Load Test |
| **Latency (Flash Sale Gate)** | Flash Sale Claim (`POST /flash-sales/{id}/claim`) | `p50 < 15ms`, `p95 < 50ms`, `p99 < 150ms` under spike load | `k6` Spike Test |
| **Async Event Lag** | Outbox → Kafka → Consumer processing | `p95 < 2 seconds` under normal load; bounded recovery under spike | Kafka Consumer Lag & end-to-end trace |
| **Availability & Recovery** | Single stateless Pod crash during load | Zero unhandled `5xx` after readiness probe transition; automatic rescheduling | Chaos pod-kill during active `k6` run |
| **Accessibility & UI Quality** | Frontend WCAG Compliance | Zero critical/serious `axe-core` violations; full keyboard navigation; loading/error/empty/retry states on every view | Playwright + `@axe-core/playwright` |

---

## 6. MVP Scope vs. Out-of-Scope Boundaries

### 6.1 In-Scope across Milestones M1–M7
- Full polyglot microservices suite (`Java 21`, `.NET 10`, `Python 3.12+`) and dual React interfaces (Storefront + Admin).
- Deterministic Payment Simulator with configurable latency, failure rates, and webhook replay.
- High-concurrency Flash Sale engine with Redis Lua atomic gate + Kafka asynchronous order materialization + PostgreSQL reconciliation.
- End-to-end observability (`OpenTelemetry`, `Prometheus`, `Grafana`, `Loki`, `Tempo`).
- On-prem multi-VM Kubernetes deployment with `Helm` and `Argo CD`.

### 6.2 Explicitly Out of Scope (Non-Goals)
- **Real PCI-DSS Payment Card Processing**: Never accept or store real credit card PAN/CVV numbers or charge real money.
- **Physical Warehouse Logistics / 3PL Carrier Integration**: Shipping is modeled only as state transitions (`CONFIRMED` → `FULFILLED`), not external FedEx/DHL API integrations.
- **Multi-Currency Tax & International Customs Engine**: All monetary values use a single configurable currency (`USD` or `VND`) with minor-unit integer representation (`BigDecimal(19,4)` or integer cents) to avoid floating-point errors.
- **Native Mobile Apps (iOS/Android)**: The React storefront is responsive for mobile viewports; native apps are out of scope.

---

## 7. Identified Requirements Gaps & Explicit Proposals

Rather than silently assuming missing requirements, we propose the following defaults for your approval:

1. **Proposal P-REQ-01 (Shopping Cart Ownership)**: Instead of creating a standalone `Cart Service`, we propose managing ephemeral shopping cart state in **Customer Service** (backed by Redis hash `cart:{customerId}` with 7-day TTL) for standard checkout, while **Flash Sale purchases bypass the standard multi-item cart** ("Direct Buy Now" of 1 SKU) to keep the hot path atomic and fast.
2. **Proposal P-REQ-02 (Flash Sale Stock Isolation)**: When a Flash Sale campaign is `APPROVED`/`WARMED`, its quota (e.g., 1,000 units) is hard-allocated from `Inventory Service` (`available_qty` decremented, `flash_sale_allocated_qty` incremented) so standard shoppers cannot accidentally buy stock reserved for an upcoming Flash Sale.
3. **Proposal P-REQ-03 (Unpaid Flash Sale Expiration Policy)**: When a user claims a Flash Sale slot but fails to pay within 10 minutes, the expired unit is returned to the Redis Flash Sale pool **only if the campaign is still `ACTIVE`**; if the campaign has already `ENDED`, the unit reconciles back to regular warehouse `available_qty`.
