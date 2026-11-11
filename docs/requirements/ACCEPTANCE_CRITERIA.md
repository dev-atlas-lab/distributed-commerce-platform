# Acceptance Criteria (`ACCEPTANCE_CRITERIA.md`)

**Milestone:** `M0.3` — Architecture Freeze and Source Foundation
**Status:** `DESIGN_ACCEPTED`
**Date:** 2026-04-11

This document defines the verifiable acceptance criteria (`AC-*`) mapped to `REQUIREMENTS.md` (`FR-*`) and `NON_FUNCTIONAL_REQUIREMENTS.md` (`NFR-*`). No requirement may transition from `DESIGN_ACCEPTED` to `TEST_VERIFIED` in `DECISION_REGISTER.md` without passing its corresponding acceptance criteria below.

---

## 1. Customer & Identity (`AC-CUS`)

- **`AC-CUS-001` (Maps to `FR-CUS-001`, `NFR-SEC-001`):**
  - *Given* an HTTP request to a protected endpoint with an OIDC ID token (`typ != at+jwt` or missing required access token claims),
  - *When* the gateway or target service validates the Bearer token,
  - *Then* the request is rejected with `401 Unauthorized` and an RFC 9457 `ProblemDetails` body.
- **`AC-CUS-002` (Maps to `FR-CUS-002`, `NFR-SEC-002`):**
  - *Given* a valid access token issued for `commerce-catalog-api` (`aud = ["commerce-catalog-api"]`),
  - *When* that token is presented to `Order` (`commerce-order-api`) or `Payment` (`commerce-payment-api`),
  - *Then* the target service rejects the request with `401 Unauthorized` or `403 Forbidden` due to audience mismatch.
- **`AC-CUS-003` (Maps to `FR-CUS-003`, `NFR-SEC-002`):**
  - *Given* a valid access token with `principal_type = CUSTOMER`,
  - *When* the caller invokes `/api/v1/admin/**` or `/internal/**`,
  - *Then* the service rejects the request with `403 Forbidden` regardless of any role strings in the payload.

---

## 2. Catalog & Search (`AC-CAT`)

- **`AC-CAT-001` (Maps to `FR-CAT-001`):**
  - *Given* a product is created or updated in the Catalog database,
  - *When* the transaction commits,
  - *Then* the `products` row and its `outbox_messages` (`ProductUpserted.v1`) row are persisted atomically in the same transaction.
- **`AC-CAT-002` (Maps to `FR-CAT-002`):**
  - *Given* products indexed with PostgreSQL `tsvector` (`search_vector`),
  - *When* a user searches by keyword, category, and price range,
  - *Then* matching active products are returned ordered by relevance (`ts_rank_cd`) without querying external search clusters in `M1`.
- **`AC-CAT-003` (Maps to `FR-CAT-003`):**
  - *Given* a new embedding model or dimension is configured in a new `embedding_index_generations` record (`status = BUILDING`),
  - *When* background workers backfill embeddings into the new generation,
  - *Then* live hybrid search queries continue serving exclusively from the single `ACTIVE` generation (`WHERE generation_id = <active_gen>`) and never mix vectors across incompatible models or dimensions.

---

## 3. Inventory (`AC-INV`)

- **`AC-INV-001` (Maps to `FR-INV-001`, `FR-INV-002`):**
  - *Given* a SKU with `available_qty = 5` and 20 concurrent `ReserveStock` requests each requesting `qty = 1` with distinct `idempotency_key`s,
  - *When* all 20 requests complete,
  - *Then* exactly 5 reservations succeed (`RESERVED`), 15 fail cleanly with `409 Conflict` (`InsufficientStock`), and `available_qty == 0` (`available_qty >= 0` always holds).
- **`AC-INV-002` (Maps to `FR-INV-003`):**
  - *Given* an active reservation (`status = RESERVED`),
  - *When* a `ConfirmReservation` or `ReleaseReservation` request or event is delivered multiple times (at-least-once delivery),
  - *Then* stock quantities are adjusted at most once, and subsequent deliveries return an idempotent success response.

---

## 4. Promotion & Flash Sale (`AC-PRO`)

- **`AC-PRO-001` (Maps to `FR-PRO-001`, `NFR-PERF-003`):**
  - *Given* a Flash Sale campaign with `remaining_stock = 100` and `per_user_limit = 1`,
  - *When* 2,000 concurrent requests attempt to claim stock across distinct and repeated `user_id`s,
  - *Then* at most 100 claims reach `CLAIMED`, no user holds more than 1 active/converted claim, and `remaining_stock` is never `< 0`.
- **`AC-PRO-002` (Maps to `FR-PRO-002`, `FR-PRO-004`):**
  - *Given* a claim that succeeded in Redis Lua (`EVALSHA`) but whose Promotion pod crashed before PostgreSQL transaction commit,
  - *When* the Reconciler runs (`fn_mp05_reconcile_insert_tombstone` + Redis atomic release Lua + `fn_mp06_reconcile_mark_redis_released`),
  - *Then* a `RELEASED_RECONCILED` tombstone is written in PostgreSQL, any late-resumed writer transaction fails to insert `CLAIMED`, and the Redis counter is incremented back by `quantity` at most once.
- **`AC-PRO-003` (Maps to `FR-PRO-003`):**
  - *Given* concurrent Expiration Worker (`fn_mp03`) and Customer Cancellation (`fn_mp04`) executions targeting the same `claim_id`,
  - *When* both execute concurrently,
  - *Then* only one transitions the row out of `CLAIMED` and increments `remaining_stock`, while the other observes `rows_affected = 0` and performs a safe idempotent no-op.
- **`AC-PRO-004` (Maps to `FR-PRO-005`, `NFR-REL-001`):**
  - *Given* concurrent execution of Writers (`fn_mp01`), Order Conversions (`fn_mp02`), Expirations (`fn_mp03`), Cancellations (`fn_mp04`), Reconcilers (`fn_mp05`/`fn_mp06`), and Rebuilders (`fn_mp08`),
  - *When* a Rebuilder acquires `FOR UPDATE` on `flash_sale_campaigns` via `fn_mp08_rebuilder_rebuild_campaign`,
  - *Then* all concurrent mutations on that campaign serialize cleanly behind the campaign lock with `0` deadlocks (`SQLSTATE 40P01`) and `0` stale-epoch commits after rebuild.
- **`AC-PRO-005` (Maps to `NFR-SEC-003`):**
  - *Given* a database connection authenticated as `promotion_app_role`,
  - *When* the session attempts a direct `INSERT`, `UPDATE`, or `DELETE` on `flash_sale_campaigns`, `flash_sale_claims`, `flash_sale_items`, `outbox_messages`, or `idempotency_records`,
  - *Then* PostgreSQL rejects the statement with `SQLSTATE 42501` (`permission denied`), whereas calling `fn_mp01`–`fn_mp08` succeeds.

---

## 5. Order & Saga Orchestration (`AC-ORD`)

- **`AC-ORD-001` (Maps to `FR-ORD-001`):**
  - *Given* a valid `POST /api/v1/orders` request with `Idempotency-Key`,
  - *When* the transaction commits,
  - *Then* the `orders` row, `order_items` rows, `outbox_messages` row, and `idempotency_records` row (`COMPLETED`) are committed in a single local transaction.
- **`AC-ORD-002` (Maps to `FR-ORD-002`):**
  - *Given* an Order in `AWAITING_PAYMENT`,
  - *When* `PaymentCaptured.v1` arrives before or after duplicate `PaymentAuthorized.v1` events,
  - *Then* the Order transitions monotonically according to its transition matrix and never regresses from `PAID` to `PAYMENT_AUTHORIZED` or `CANCELLED`.
- **`AC-ORD-003` (Maps to `FR-ORD-004`):**
  - *Given* an Order whose reservation TTL expires and transitions to `CANCELLED_TIMEOUT`,
  - *When* a late `PaymentCaptured.v1` webhook arrives from the payment provider afterward,
  - *Then* the Order remains in a cancelled terminal state and emits a `CompensatingRefundRequested.v1` outbox event within the same transaction.

---

## 6. Payment & Webhook Processing (`AC-PAY`)

- **`AC-PAY-001` (Maps to `FR-PAY-001`, `FR-PAY-003`):**
  - *Given* provider webhooks for `CaptureSucceeded` arriving before `AuthSucceeded` (out-of-order) or delivered 3 times (duplicate),
  - *When* the Payment service processes each webhook,
  - *Then* raw webhooks are recorded idempotently in `payment_webhook_events`, `PaymentAttempt` transitions to `CAPTURED` without throwing an invalid transition error on the late `AuthSucceeded` event, and `PaymentCaptured.v1` is emitted exactly once to `outbox_messages`.
- **`AC-PAY-002` (Maps to `FR-PAY-004`):**
  - *Given* a `Refund` record created with a deterministic `provider_refund_idempotency_key`,
  - *When* the refund worker retries after a network timeout,
  - *Then* it reuses the exact same `provider_refund_idempotency_key` so the external payment provider executes at most one refund transfer.

---

## 7. Idempotency & Mutating Command Execution (`AC-IDEM`)

- **`AC-IDEM-001` (Maps to `FR-IDEM-001`):**
  - *Given* a completed `Idempotency-Key` for `(scope, principal_id)`,
  - *When* the client retries with the same `Idempotency-Key` and identical `request_hash`,
  - *Then* the stored status code and response payload are returned without re-executing mutations; if `request_hash` differs, `422 Unprocessable Entity` is returned.
- **`AC-IDEM-002` (Maps to `FR-IDEM-002`, `FR-IDEM-003`):**
  - *Given* a Type II external provider mutation whose worker crashed after acquiring `lease_generation = 1` and persisting `downstream_operation_id`,
  - *When* the lease expires,
  - *Then* a recovery worker transitions the record to `RECONCILING` with `lease_generation = 2`, queries the provider using the immutable `downstream_operation_id`, and never issues a blind duplicate provider mutation; if unresolved after `15 minutes`, it transitions to `MANUAL_INTERVENTION_REQUIRED`.

---

## 8. Transactional Outbox & Consumer Inbox (`AC-OUT`)

- **`AC-OUT-001` (Maps to `FR-OUT-001`):**
  - *Given* multiple unpublished `outbox_messages` rows for the same `aggregate_id` (`aggregate_version = 1, 2, 3`),
  - *When* an Outbox Relay polling cycle executes,
  - *Then* the relay selects at most the lowest unpublished `aggregate_version` per `aggregate_id` per batch (`DISTINCT ON (aggregate_id) ... ORDER BY aggregate_id, aggregate_version ASC`) and publishes it with `partition_key = aggregate_id`.
- **`AC-OUT-002` (Maps to `FR-OUT-002`):**
  - *Given* a Consumer receiving events for an aggregate where `last_applied_version == 1`,
  - *When* event `version = 1` arrives again (duplicate), event `version = 3` arrives early (gap), and event `version = 2` arrives subsequently,
  - *Then* `version = 1` is ignored as an idempotent no-op, `version = 3` is deferred/retried without advancing state, `version = 2` is applied advancing `last_applied_version` to `2`, and `version = 3` is subsequently applied advancing `last_applied_version` to `3`.

---

## 9. AI Worker & Chaos Fault Injection (`AC-AI` & `AC-CHAOS`)

- **`AC-AI-001` (Maps to `FR-AI-001`, `FR-AI-002`, `FR-AI-003`):**
  - *Given* an AI shopping assistant query recommending a product or checking Flash Sale eligibility,
  - *When* the `ai-worker` formulates its response,
  - *Then* live price and availability are fetched via read-only Catalog/Inventory/Promotion tools, no direct order/payment/claim write is executed by the LLM, and timeout/failure in the AI provider degrades gracefully without affecting checkout APIs.
- **`AC-CHAOS-001` (Maps to `NFR-SEC-004`):**
  - *Given* any service (`Java`, `.NET`, or `Python`) started with a production environment indicator and `FAULT_INJECTION_ENABLED=true`,
  - *When* the process initializes its startup guards,
  - *Then* the process immediately throws a fatal configuration exception and refuses to start (`fail-closed`).
