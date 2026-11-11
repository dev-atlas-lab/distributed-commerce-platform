# Functional & Distributed Consistency Requirements (`REQUIREMENTS.md`)

- **Document ID:** `DCP-DOC-REQ-001`
- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Milestone:** `M0.3 — Architecture Freeze & Source Foundation`
- **Status:** `DESIGN_ACCEPTED`
- **Last Updated:** 2026-11-11

---

## 1. Bounded Context & Service Mapping

| Bounded Context | Service Directory (`src/`) | Runtime Stack | Database (`PostgreSQL 17`) | Primary Decisions & ADRs |
| :--- | :--- | :--- | :--- | :--- |
| **Edge Gateway** | `src/gateways/api-gateway` | `.NET 10` (`YARP`) | Stateless (`Redis` rate limits) | `Q5`, `CH-05`, `CH-07`, `ADR-0006`, `ADR-0011` |
| **Customer & Identity** | `src/services/customer` | `.NET 10` (`ASP.NET Core`) | `customer_db` + `Redis` Cart | `Q5`, `CH-05`, `ADR-0001`, `ADR-0006` |
| **Catalog & Search** | `src/services/catalog` | `Java 21` (`Spring Boot 3.4`) | `product_db` (`FTS` + `pg_trgm`) + `MinIO` | `Q6`, `CH-06`, `ADR-0001`, `ADR-0007` |
| **Inventory Ledger** | `src/services/inventory` | `Java 21` (`Spring Boot 3.4`) | `inventory_db` | `CH-03`, `CH-04`, `ADR-0002`, `ADR-0005` |
| **Promotion & Flash Sale** | `src/services/promotion` | `.NET 10` (`ASP.NET Core`) | `promotion_db` + `Redis 7.4` Lua | `Q4`, `CH-01`, `CH-03`, `ADR-0005` |
| **Order & Saga** | `src/services/order` | `Java 21` (`Spring Boot 3.4`) | `order_db` | `CH-02`, `CH-03`, `CH-04`, `ADR-0003`, `ADR-0004` |
| **Payment & Webhooks** | `src/services/payment` | `Java 21` (`Spring Boot 3.4`) | `payment_db` | `CH-02`, `CH-03`, `CH-04`, `ADR-0003`, `ADR-0004` |
| **Notification Worker** | `src/services/notification` | `.NET 10` (`Worker Service`) | `notification_db` (or stateless + Inbox) | `CH-04`, `ADR-0001`, `ADR-0010` |
| **AI Assistant & RAG** | `src/workers/ai-worker` | `Python 3.12+` (`FastAPI`) | `ai_agent_db` (`pgvector`) | `Q7`, `CH-06`, `ADR-0008` |

---

## 2. Functional Requirements by Bounded Context

### 2.1 Customer, Identity & Cart (`FR-CUS-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-CUS-001`** | **OIDC Discovery & Asymmetric `RS256` Token Issuance**: `customer` service MUST publish `/.well-known/openid-configuration` and `/.well-known/jwks.json` and sign access tokens (`typ: "at+jwt"`, `aud: "commerce-api"`) and OIDC ID tokens (`typ: "JWT"`, `aud: "commerce-web-spa"`) using `RS256` with an active `kid`. | `Q5`, `CH-05`, `ADR-0006` | `AC-CUS-001` |
| **`FR-CUS-002`** | **Refresh Token Rotation & Reuse Detection**: Refresh tokens MUST be stored as `SHA-256` hashes in `customer_db` with family tracking; presenting a previously rotated refresh token MUST revoke the entire token family immediately. | `Q5`, `ADR-0006` | `AC-CUS-002` |
| **`FR-CUS-003`** | **Redis Shopping Cart with Price/Stock Revalidation**: Customer carts MUST be persisted in Redis (`cart:{customer_id}`, `7d` TTL) and revalidated against authoritative `catalog` prices and `inventory` availability at checkout initiation. | `ADR-0001` | `AC-CUS-003` |

### 2.2 Catalog & Product Search (`FR-CAT-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-CAT-001`** | **Product & SKU Lifecycle Management**: `catalog` service MUST manage categories, products, SKUs, JSONB technical attributes, and pre-signed MinIO image upload URLs, emitting `ProductUpserted` (`aggregate_version` incremented by `1`) via its transactional Outbox on every state mutation. | `ADR-0001`, `ADR-0003`, `CH-04` | `AC-CAT-001` |
| **`FR-CAT-002`** | **Cache-Aside Product Read Model**: `GET /api/v1/products/{id}` MUST use Redis cache-aside (`product:v1:{id}`, `15m` TTL with jitter) and invalidate/update the key upon `ProductUpserted`. | `ADR-0001` | `AC-CAT-002` |
| **`FR-CAT-003`** | **PostgreSQL 17 Hybrid FTS + Trigram + JSONB Search**: `GET /api/v1/products/search` MUST execute weighted `tsvector` (`A`: title, `B`: brand/category, `C`: description), `pg_trgm` fuzzy fallback, and `JSONB` `@>` attribute filtering behind a `ProductSearchPort` abstraction. | `Q6`, `CH-06`, `ADR-0007` | `AC-CAT-003` |

### 2.3 Inventory Management & Double-Entry Stock Ledger (`FR-INV-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-INV-001`** | **Deadlock-Free Multi-SKU Conditional Reservation**: `inventory` service MUST sort multi-line reservation items by `sku_id ASC` before executing conditional atomic SQL (`UPDATE stock_items SET available_qty = available_qty - :qty, reserved_qty = reserved_qty + :qty WHERE sku_id = :skuId AND available_qty >= :qty`). If any SKU fails, the entire transaction MUST roll back. | `ADR-0005` | `AC-INV-001` |
| **`FR-INV-002`** | **Immutable Double-Entry Stock Ledger**: Every mutation to `available_qty`, `reserved_qty`, or `sold_qty` MUST append an immutable audit row to `stock_ledger_entries` (`RESERVE`, `CONFIRM`, `RELEASE`, `ADJUST`) within the same database transaction. | `ADR-0002`, `ADR-0005` | `AC-INV-002` |
| **`FR-INV-003`** | **Idempotent Reservation Release & Confirmation**: Reservation confirmation (`RESERVED -> CONFIRMED`) and release (`RESERVED -> RELEASED` on order expiry/cancellation) MUST be idempotent on `(order_id, operation_type)` and safe under duplicate Kafka event delivery. | `CH-03`, `CH-04`, `ADR-0003` | `AC-INV-003` |

### 2.4 Promotion & Flash Sale Concurrency (`FR-PRO-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-PRO-001`** | **Redis Atomic Lua Admission Gate (`flash_sale_claim.lua`)**: Flash Sale claim requests MUST first execute `EVALSHA` in Redis (`flash_sale_claim.lua`) to atomically validate campaign `ACTIVE` status, `epoch`, per-customer limit (`max_qty_per_user`), and remaining stock (`stock >= qty`), returning `(claim_id, campaign_epoch, intent_lease_expires_at = T + 30s)`. | `Q4`, `CH-01`, `ADR-0005` | `AC-PRO-001` |
| **`FR-PRO-002`** | **Privilege-Encapsulated `SECURITY DEFINER` Claim Persistence (`fn_mp01`–`fn_mp08`)**: All 8 Flash Sale mutation paths in `promotion_db` MUST execute exclusively through imperative PL/pgSQL `SECURITY DEFINER` stored procedures owned by a non-login, non-superuser role (`promotion_proc_owner`) with fixed `SET search_path = pg_catalog, public`, acquiring locks in strict order: `1. flash_sale_campaigns (FOR SHARE/UPDATE) -> 2. flash_sale_claims (by claim_id ASC) -> 3. flash_sale_items (by sku_id ASC) -> 4. outbox_messages -> 5. idempotency_records`. Direct `INSERT, UPDATE, DELETE` on `flash_sale_campaigns`, `flash_sale_claims`, and `flash_sale_items` MUST be revoked from `promotion_app_role`. | `CH-01`, `ADR-0005` | `AC-PRO-002` |
| **`FR-PRO-003`** | **Fenced Unacknowledged Claim Reconciliation (`ABANDONED_FENCED`)**: When a Redis intent lease (`30s`) expires without `CLAIMED_RESERVED` in `promotion_db`, the reconciler MUST invoke `fn_mp02_reconcile_fenced` to insert `status = 'ABANDONED_FENCED'` (`ON CONFLICT (claim_id) DO NOTHING`). If a delayed Writer arrives after `ABANDONED_FENCED` is committed, `fn_mp01_writer_claim` MUST abort and return `409 Conflict (CLAIM_LEASE_EXPIRED_FENCED)`. | `Q4`, `CH-01`, `ADR-0005` | `AC-PRO-003` |
| **`FR-PRO-004`** | **PostgreSQL-Gated & Epoch-Validated Active Pool Restock (`flash_sale_release.lua`)**: When a claim transitions to `ABANDONED_FENCED`, `EXPIRED`, or `CANCELLED` while the campaign is `ACTIVE`, the worker MUST verify `stock_returned_to_redis == FALSE`, invoke `flash_sale_release.lua` (validating `redis_epoch == release_epoch` and `HSETNX released_claims {claim_id}` and clamping `new_stock <= allocated_quota`), and finalize via `fn_mp04_restock_finalize`. | `Q4`, `CH-01`, `ADR-0005` | `AC-PRO-004` |
| **`FR-PRO-005`** | **Exclusive-Lock Redis Rebuild (`REBUILDING_GATE`)**: On Redis restart or epoch mismatch, `promotion` service MUST invoke `fn_mp07_rebuilder_fence_and_snapshot`, which acquires an exclusive `FOR UPDATE` lock on `flash_sale_campaigns` (waiting for all prior `FOR SHARE` transactions to complete), increments `current_epoch`, marks prior unreleased terminal claims as `stock_returned_to_redis = TRUE`, computes exact remaining stock (`allocated_quota - SUM(active_claims)`), rebuilds Redis under the new epoch, and reactivates via `fn_mp08_campaign_lifecycle`. | `CH-01`, `ADR-0005` | `AC-PRO-005` |

### 2.5 Order Management & Hybrid Fulfillment Saga (`FR-ORD-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-ORD-001`** | **Explicit `Order` State Machine**: `order` service MUST enforce the explicit `Order` transition matrix (`PENDING_RESERVATION -> RESERVATION_FAILED | AWAITING_PAYMENT -> PAID -> FULFILLING -> COMPLETED`, or `AWAITING_PAYMENT -> EXPIRED | CANCELLED -> REFUND_PENDING -> REFUNDED`) and reject invalid state transitions. | `CH-02`, `ADR-0004` | `AC-ORD-001` |
| **`FR-ORD-002`** | **Hybrid Saga Orchestration**: `order` service MUST orchestrate stock reservation (`inventory`), coupon/flash-sale verification (`promotion`), and payment lifecycle (`payment`), persisting Saga step state and Outbox commands in the same local transaction. | `CH-02`, `CH-04`, `ADR-0004` | `AC-ORD-002` |
| **`FR-ORD-003`** | **Deterministic Payment Timeout & Compensation**: If an order in `AWAITING_PAYMENT` reaches `payment_expires_at`, `order` service MUST transition the order to `EXPIRED`, emit `ReleaseStockCommand` / `VoidPaymentCommand`, and never rely on a wall-clock buffer for payment correctness. | `CH-02`, `ADR-0004` | `AC-ORD-003` |
| **`FR-ORD-004`** | **Late Payment Capture Auto-Refund Compensation**: If `PaymentCaptured` arrives for an order that is already `EXPIRED` or `CANCELLED` (or already paid by an earlier `PaymentAttempt`), the Saga MUST transition to `REFUND_PENDING` and trigger an idempotent refund without resurrecting the expired inventory reservation. | `CH-02`, `ADR-0004` | `AC-ORD-004` |

### 2.6 Payment State Machine & Webhook Processing (`FR-PAY-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-PAY-001`** | **Explicit `PaymentAttempt` State Machine**: `payment` service MUST model `1:N` `PaymentAttempt` entities per `order_id` with explicit transition validation across `INITIATED`, `AUTHORIZED`, `CAPTURE_PENDING`, `CAPTURED`, `VOID_PENDING`, `VOIDED`, `REFUND_PENDING`, `PARTIALLY_REFUNDED`, `REFUNDED`, and `FAILED` (never using a scalar numeric state rank). | `CH-02`, `ADR-0004` | `AC-PAY-001` |
| **`FR-PAY-002`** | **Separation of Provider-Reported Facts from Internal State**: `payment_attempts` MUST store `provider_authorized_at`, `provider_captured_at`, `provider_voided_at`, and `provider_refunded_at` strictly from provider-reported webhook facts; receiving a direct `payment.captured` webhook when `provider_authorized_at IS NULL` MUST NOT fabricate `provider_authorized_at`. | `CH-02`, `ADR-0004` | `AC-PAY-002` |
| **`FR-PAY-003`** | **Single-Transaction Webhook Deduplication & Out-of-Order Handling**: HMAC-SHA256 verified webhooks MUST insert into `payment_webhook_logs (provider_event_id PK)`, mutate `payment_attempts` (and `refund_requests` if applicable), and insert into `outbox_messages` in a **single local PostgreSQL transaction**. Duplicate `provider_event_id`s or out-of-order `payment.authorized` arriving after `CAPTURED` MUST return `200 OK` without emitting duplicate Outbox events. | `CH-02`, `ADR-0003`, `ADR-0004` | `AC-PAY-003` |
| **`FR-PAY-004`** | **Late Capture After Void Idempotent Auto-Refund**: If a `payment.captured` webhook arrives when `PaymentAttempt.status` is `VOID_PENDING` or `VOIDED`, `payment` service MUST transition the attempt to `REFUND_PENDING` and insert a deterministic row into `refund_requests` (`UNIQUE (attempt_id, reason_code)` and `refund_idempotency_key UNIQUE`) in the same transaction. | `CH-02`, `ADR-0004` | `AC-PAY-004` |

### 2.7 Cross-Cutting Idempotency & Outbox/Inbox Messaging (`FR-IDEM-xxx`, `FR-OUT-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-IDEM-001`** | **Canonical Payload Hashing & Concurrent Duplicate Handling**: All mutating HTTP endpoints (`POST`/`PUT`/`PATCH`) requiring `Idempotency-Key` MUST compute RFC 8785 JCS `SHA-256` over `(HTTP_METHOD, PATH, CANONICAL_BODY)`: mismatched payload hash with the same key MUST return `422 Unprocessable Entity (IDEMPOTENCY_PAYLOAD_MISMATCH)`; a concurrent duplicate while `status IN ('STARTED', 'RECONCILING')` MUST return `409 Conflict (IDEMPOTENCY_IN_PROGRESS)` with `Retry-After: 2`. | `CH-03`, `ADR-0003` | `AC-IDEM-001` |
| **`FR-IDEM-002`** | **Class B Fenced Lease & Mandatory `RECONCILING` State**: For operations with external side effects (Class B), an expired lease MUST NOT blindly re-execute the external call. A recovering worker MUST increment `lease_generation`, transition to `RECONCILING`, and query downstream state using the immutable `downstream_operation_id` assigned at `lease_generation = 1`. Local DB completion MUST verify `WHERE lease_generation = :expectedGen`. | `CH-03`, `ADR-0003` | `AC-IDEM-002` |
| **`FR-IDEM-003`** | **Type I vs. Type II Downstream `NOT_FOUND` Handling**: During `RECONCILING`, if a Type I downstream (authoritative read-after-write + idempotent on `downstream_operation_id`) returns `NOT_FOUND`, the worker may resume execution with the same `downstream_operation_id`; if a Type II downstream (eventually consistent / non-idempotent) returns `NOT_FOUND`, re-execution is forbidden and the record MUST remain in `RECONCILING` until resolved or escalated to `MANUAL_INTERVENTION_REQUIRED` after `15 minutes`. | `CH-03`, `HD-02`, `ADR-0003` | `AC-IDEM-003` |
| **`FR-OUT-001`** | **Transactional Outbox with `aggregate_id` Partition Key & Head-Event Claim**: Services MUST insert integration events into `outbox_messages` (`partition_key = aggregate_id`, monotonic `aggregate_version`) in the same DB transaction as domain mutations. Relay workers coordinated via PostgreSQL leases (`outbox_relay_shards`) MUST claim **at most one event (the lowest unpublished `aggregate_version`) per `aggregate_id` per cycle** (`DISTINCT ON (aggregate_id)`). | `CH-04`, `ADR-0003`, `ADR-0010` | `AC-OUT-001` |
| **`FR-OUT-002`** | **Atomic Consumer Inbox & Strict `last_applied_version + 1` Application Gate**: Consumers MUST NOT assume strict Kafka log append ordering across stale/competing relay processes. Inside a single database transaction, the consumer MUST insert into `inbox_messages (event_id, consumer_group)` and validate `incoming.aggregate_version` against `last_applied_version`:<br>• `incoming.version <= last_applied_version`: treat as stale/duplicate (idempotent no-op).<br>• `incoming.version == last_applied_version + 1`: apply state transition and set `last_applied_version = incoming.version`.<br>• `incoming.version > last_applied_version + 1`: defer/retry via retry topic until the missing version arrives (never silently skip a version gap). | `CH-04`, `ADR-0003`, `ADR-0010` | `AC-OUT-002` |

### 2.8 AI Shopping & Operations Assistant (`FR-AI-xxx`)
| ID | Requirement Statement | Traceability | Acceptance Criterion ID |
| :--- | :--- | :--- | :--- |
| **`FR-AI-001`** | **Multi-Provider LLM & Embedding Port**: `ai-worker` MUST abstract OpenAI, Google Gemini, and Anthropic Claude behind a unified provider interface configurable via environment variables without changing domain or tool-dispatch code. | `Q7`, `ADR-0008` | `AC-AI-001` |
| **`FR-AI-002`** | **Zero-Privilege JWT-Bound Tool Execution & HITL Approval**: `ai-worker` MUST have zero database credentials for any business service database (`product_db`, `order_db`, `inventory_db`, `payment_db`, `promotion_db`, `customer_db`), MUST bind `customer_id` exclusively from the verified `Bearer` JWT (never from LLM tool arguments), and MUST require explicit Human-in-the-Loop confirmation before executing any state-mutating tool (`cancel_order`, `prepare_cart`). | `Q7`, `ADR-0008` | `AC-AI-002` |
| **`FR-AI-003`** | **Generation-Isolated `pgvector` RAG Retrieval**: `ai_agent_db` MUST track embedding model metadata in `embedding_index_generations` (`provider_name`, `model_id`, `model_version`, `dimensions`, `index_storage_type`), enforce `CHECK` constraints for `pgvector` HNSW index ceilings (`<= 2,000d` for `VECTOR_FP32`, `<= 4,000d` for `HALFVEC_FP16`), and filter all similarity queries by the single active `generation_id`. | `CH-06`, `ADR-0008` | `AC-AI-003` |
