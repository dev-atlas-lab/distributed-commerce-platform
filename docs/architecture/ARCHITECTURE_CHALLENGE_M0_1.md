# Architecture Challenge Refinement & Adversarial Verification (`M0.2.4` — `CH-01` through `CH-07`)

- **Document ID:** `DCP-DOC-ARCH-008`
- **Verification Reports:** [`M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md), [`M0_2_3_CONCURRENCY_CORRECTIONS.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_3_CONCURRENCY_CORRECTIONS.md), [`M0_2_4_FINAL_FENCING_REVIEW.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md)
- **Status:**
  - Foundational Decisions (`Q1–Q7`): **`ACCEPTED`**
  - `CH-01` through `CH-07`: **`PROPOSED` (Adversarially Verified & Fencing-Hardened in `M0.2.4` — Pending Explicit Human Sign-Off)**
- **Last Updated:** 2026-11-11

---

## Executive Overview of `M0.2.2` – `M0.2.4` Adversarial Corrections

In `M0.2.2`, `M0.2.3`, and `M0.2.4`, we performed an adversarial verification of all seven challenge specifications (`CH-01` through `CH-07`) against concurrency races, crash windows, SQL conflict clauses, network partitions, and privilege escalation vectors (`F-01` through `F-16` in [`M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md), [`M0_2_3_CONCURRENCY_CORRECTIONS.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_3_CONCURRENCY_CORRECTIONS.md), and [`M0_2_4_FINAL_FENCING_REVIEW.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md)):
- **`CH-01` (`M0.2.4` Final Fencing Review — `F-11`, `F-12`, `F-15`)**: Enumerated all **8 Flash Sale mutation paths (`MP-01` through `MP-08`)** requiring explicit `campaign_guard` (`FOR SHARE` / `FOR UPDATE` on `flash_sale_campaigns` as CTE Step 1) to guarantee strict `Table 1 -> Table 2 -> Table 3` lock order and deadlock freedom; upgraded database triggers on **both** `flash_sale_claims` and `flash_sale_items` (`BEFORE INSERT OR UPDATE OR DELETE`) as an engine-level invariant; and strictly separated the **Primary Correctness Mechanism** (PostgreSQL `FOR SHARE` vs. `FOR UPDATE` lock mutual exclusion) from **Operational Liveness Policies** (`3s` session timeouts and `pg_terminate_backend`).
- **`CH-02`**: Removed fabricated `authorized_at = COALESCE(authorized_at, ts)` on direct capture events (`F-04`), separated **provider-reported facts** (`provider_authorized_at`, `provider_captured_at`) from internal state transitions, and added a deterministic `refund_requests` table (`UNIQUE (attempt_id, reason_code)`) for late-capture-after-void auto-refunds (`F-05`).
- **`CH-03`**: Explicitly analyzed why local `lease_generation` fences **local DB state** while downstream side-effect deduplication relies on passing immutable `downstream_operation_id` (and `lease_generation` for Redis) to the downstream system (`F-06`), and distinguished **Authoritative `NOT_FOUND`** from **Eventually Consistent `NOT_FOUND`** (`MANUAL_INTERVENTION_REQUIRED` escalation).
- **`CH-04` (`M0.2.4` Final Fencing Review — `F-13`, `F-14`, `F-16`)**: Eliminated the `initTransactions()` ownership race (`F-16`) via a **Dedicated Shard Dispatcher (`StatefulSet` ordinal pinning + single worker thread per shard)** and a **Two-Stage Shard Lease State Machine (`INITIALIZING -> ACTIVE`)** in `outbox_relay_shards` (`owner_backend_pid`, `15s` monotonic pre-init watchdog vs. `35s` `initializing_deadline`, `ACTIVATE_SHARD_CAS` gate before any `Phase 1` query, and self-healing `ProducerFencedException` recovery), while preserving **Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)**.
- **`CH-05`**: Replaced the flat role union (`F-08`) with **Principal-Type Separation** (M2M `client_credentials` tokens can never hold human `CUSTOMER`/`ADMIN_*` roles) and **Target-Service Scoped Role Extraction** (`resource_access[target_service_id].roles`).
- **`CH-06`**: Removed unverified universal recall/memory claims (`F-09`) and marked `Recall@10` and `p95` latency as **`NEEDS_EVIDENCE` (Empirical Benchmark Targets)** while preserving the verified `pgvector` `2,000d` (`vector`) vs. `4,000d` (`halfvec`) ANN index ceilings.
- **`CH-07`**: Added a **Fail-Closed Production Startup Guard** (`F-10`): if `ENVIRONMENT == 'production'` (or `PRODUCTION_LOCK == 'true'`) and `FAULT_INJECTION_ENABLED == 'true'`, the service aborts startup immediately with `FatalSecurityConfigurationException`.

---

## `CH-01`: Redis / PostgreSQL Flash Sale Claim Lifecycle, Lock-Serialized Epoch Fencing & Rebuild

- **Status:** `PROPOSED` (Redesigned & Logically Verified in `M0.2.3` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md)
- **Detailed Concurrency Report:** [`M0_2_3_CONCURRENCY_CORRECTIONS.md#2-ch-01-redesign`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_3_CONCURRENCY_CORRECTIONS.md)

### 1. Strict Lock Acquisition Order & Single-Statement CTE Mutations (`promotion_db`)

To prevent deadlocks and guarantee that **no old-epoch transaction can ever commit after `TX_REBUILDER` begins reading the authoritative snapshot** (without relying on any fixed sleep timer), every Flash Sale transaction acquires locks in strict topological order:
$$\text{1. } \texttt{flash\_sale\_campaigns} \longrightarrow \text{2. } \texttt{flash\_sale\_claims} \longrightarrow \text{3. } \texttt{flash\_sale\_items} \longrightarrow \text{4. } \texttt{outbox\_messages} \longrightarrow \text{5. } \texttt{idempotency\_records}$$

```mermaid
stateDiagram-v2
    [*] --> REDIS_INTENT_LEASED : Step 1 - Redis Lua EVALSHA (claim_id, campaign_epoch, TTL=30s)
    REDIS_INTENT_LEASED --> CLAIMED_RESERVED : Step 2 - Single-CTE DB TX (FOR SHARE campaign_guard + claims + items + outbox + idem)
    REDIS_INTENT_LEASED --> ABANDONED_FENCED : Reconciler Single-CTE TX (FOR SHARE campaign_guard + ABANDONED_FENCED + release_epoch)
    CLAIMED_RESERVED --> ORDER_MATERIALIZED : Order Service materializes FlashSaleOrder
    CLAIMED_RESERVED --> EXPIRED : Payment window (10m) expires -> FOR SHARE campaign_guard -> release_epoch -> Redis release
    CLAIMED_RESERVED --> CANCELLED : Customer cancels -> FOR SHARE campaign_guard -> release_epoch -> Redis release
    ORDER_MATERIALIZED --> PAYMENT_CONFIRMED : PaymentCaptured event processed
    ORDER_MATERIALIZED --> EXPIRED : Order payment expires -> FOR SHARE campaign_guard -> release_epoch -> Redis release
    ORDER_MATERIALIZED --> CANCELLED : Order cancelled -> FOR SHARE campaign_guard -> release_epoch -> Redis release
    PAYMENT_CONFIRMED --> [*]
    EXPIRED --> [*]
    CANCELLED --> [*]
    ABANDONED_FENCED --> [*]
```

#### 1.1 Schema & Engine-Level Epoch Fencing Trigger (`flash_sale_campaigns` & `flash_sale_claims`)
```sql
CREATE TABLE flash_sale_campaigns (
    campaign_id             UUID PRIMARY KEY,
    name                    VARCHAR(128) NOT NULL,
    status                  VARCHAR(32)  NOT NULL CHECK (status IN (
                                'DRAFT', 'APPROVED', 'WARMED', 'ACTIVE',
                                'REBUILDING_GATE', 'ENDED', 'RECONCILED'
                            )),
    current_epoch           BIGINT       NOT NULL DEFAULT 1,
    starts_at               TIMESTAMPTZ  NOT NULL,
    ends_at                 TIMESTAMPTZ  NOT NULL,
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE flash_sale_claims (
    claim_id                UUID PRIMARY KEY,
    campaign_id             UUID NOT NULL REFERENCES flash_sale_campaigns(campaign_id),
    campaign_epoch          BIGINT NOT NULL,
    release_epoch           BIGINT NULL,
    sku_id                  UUID NOT NULL,
    customer_id             UUID NOT NULL,
    idempotency_key         VARCHAR(128) NOT NULL,
    quantity                INTEGER NOT NULL CHECK (quantity > 0),
    status                  VARCHAR(32) NOT NULL CHECK (status IN (
                                'CLAIMED_RESERVED',
                                'ORDER_MATERIALIZED',
                                'PAYMENT_CONFIRMED',
                                'CANCELLED',
                                'EXPIRED',
                                'ABANDONED_FENCED'
                            )),
    intent_lease_expires_at TIMESTAMPTZ NOT NULL,
    payment_expires_at      TIMESTAMPTZ NOT NULL,
    stock_returned_to_redis BOOLEAN NOT NULL DEFAULT FALSE,
    version                 BIGINT NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_flash_claim_idem UNIQUE (campaign_id, customer_id, idempotency_key)
);

CREATE UNIQUE INDEX uq_flash_active_customer_sku
    ON flash_sale_claims (campaign_id, sku_id, customer_id)
    WHERE status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED');

-- Defense-in-depth trigger: enforces FOR SHARE lock on flash_sale_campaigns + ACTIVE status + matching epoch
CREATE OR REPLACE FUNCTION fn_enforce_campaign_epoch_and_lock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_current_epoch BIGINT;
    v_status        VARCHAR(32);
BEGIN
    SELECT current_epoch, status
      INTO v_current_epoch, v_status
      FROM flash_sale_campaigns
     WHERE campaign_id = NEW.campaign_id
       FOR SHARE;

    IF NOT FOUND OR v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_ACTIVE_FENCED: campaign=% status=%', NEW.campaign_id, v_status
            USING ERRCODE = 'P0001';
    END IF;

    IF TG_OP = 'INSERT' AND NEW.campaign_epoch <> v_current_epoch THEN
        RAISE EXCEPTION 'STALE_CAMPAIGN_EPOCH_FENCED: claim_epoch=% current_epoch=%',
            NEW.campaign_epoch, v_current_epoch
            USING ERRCODE = 'P0002';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_campaign_epoch_and_lock
BEFORE INSERT OR UPDATE OF status ON flash_sale_claims
FOR EACH ROW
WHEN (NEW.status IN ('CLAIMED_RESERVED', 'ABANDONED_FENCED', 'EXPIRED', 'CANCELLED')
      AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status))
EXECUTE FUNCTION fn_enforce_campaign_epoch_and_lock();
```

#### 1.2 Exact Single-Statement Data-Modifying CTE for Writer (`TX_WRITER`)
All five steps execute inside **one single-roundtrip SQL statement** (with session timeouts `statement_timeout = '3s'`, `idle_in_transaction_session_timeout = '3s'`, `lock_timeout = '2s'`), eliminating any possibility of a client JVM/.NET pause between statements while holding an open transaction:
```sql
WITH
campaign_guard AS (
    SELECT campaign_id, current_epoch
    FROM flash_sale_campaigns
    WHERE campaign_id = :campaignId
      AND current_epoch = :redisClaimEpoch
      AND status = 'ACTIVE'
    FOR SHARE
),
inserted_claim AS (
    INSERT INTO flash_sale_claims (
        claim_id, campaign_id, campaign_epoch, sku_id, customer_id, idempotency_key,
        quantity, status, intent_lease_expires_at, payment_expires_at
    )
    SELECT
        :claimId, cg.campaign_id, cg.current_epoch, :skuId, :customerId, :idempotencyKey,
        :qty, 'CLAIMED_RESERVED', :intentExpiresAt, :paymentExpiresAt
    FROM campaign_guard cg
    ON CONFLICT (claim_id) DO NOTHING
    RETURNING claim_id, campaign_id, sku_id, quantity, status
),
updated_item AS (
    UPDATE flash_sale_items fsi
    SET claimed_count = fsi.claimed_count + ic.quantity
    FROM inserted_claim ic
    WHERE fsi.campaign_id = ic.campaign_id
      AND fsi.sku_id = ic.sku_id
      AND fsi.claimed_count + ic.quantity <= fsi.allocated_quota
    RETURNING fsi.sku_id
),
inserted_outbox AS (
    INSERT INTO outbox_messages (
        event_id, shard_id, aggregate_type, aggregate_id, aggregate_version,
        event_type, topic, partition_key, payload, headers
    )
    SELECT
        :eventId, mod(abs(hashtext(:customerId::text)), 16), 'FlashSaleClaim', ic.claim_id::text, 1,
        'commerce.flashsale.slot_claimed.v1', 'commerce.flashsale.events.v1',
        :customerId::text, :payloadJsonb, :headersJsonb
    FROM inserted_claim ic
    JOIN updated_item ui ON ui.sku_id = ic.sku_id
    RETURNING event_id
),
completed_idem AS (
    UPDATE idempotency_records
    SET status = 'COMPLETED_SUCCESS', http_status_code = 202,
        response_payload = :responseJsonb, updated_at = NOW()
    WHERE scope_owner_id = :customerId
      AND endpoint_id = 'POST:/api/v1/flash-sales/claim'
      AND idempotency_key = :idempotencyKey
      AND lease_generation = :expectedLeaseGen
      AND EXISTS (SELECT 1 FROM inserted_outbox)
    RETURNING idempotency_key
)
SELECT
    (SELECT COUNT(*) FROM campaign_guard) AS epoch_valid,
    (SELECT status FROM inserted_claim) AS inserted_status,
    (SELECT COUNT(*) FROM updated_item) AS quota_updated,
    (SELECT status FROM flash_sale_claims WHERE claim_id = :claimId) AS existing_status;
```

#### 1.3 Exact Single-Statement CTE for Reconciler (`TX_RECONCILER`) & Epoch-Checked `flash_sale_release.lua`
```sql
WITH campaign_guard AS (
    SELECT campaign_id, current_epoch
    FROM flash_sale_campaigns
    WHERE campaign_id = :campaignId
      AND current_epoch = :redisClaimEpoch
      AND status = 'ACTIVE'
    FOR SHARE
),
fenced_claim AS (
    INSERT INTO flash_sale_claims (
        claim_id, campaign_id, campaign_epoch, release_epoch, sku_id, customer_id,
        idempotency_key, quantity, status, intent_lease_expires_at, payment_expires_at,
        stock_returned_to_redis
    )
    SELECT
        :claimId, cg.campaign_id, cg.current_epoch, cg.current_epoch, :skuId, :customerId,
        :idempotencyKey, :qty, 'ABANDONED_FENCED', :intentExpiresAt, :intentExpiresAt,
        FALSE
    FROM campaign_guard cg
    ON CONFLICT (claim_id) DO NOTHING
    RETURNING claim_id, status, release_epoch
)
SELECT
    (SELECT COUNT(*) FROM campaign_guard) AS epoch_valid,
    (SELECT status FROM fenced_claim) AS fenced_status,
    (SELECT release_epoch FROM fenced_claim) AS release_epoch,
    (SELECT status FROM flash_sale_claims WHERE claim_id = :claimId) AS existing_status;
```
- **Why Cross-Epoch Releases Cannot Inflate Stock (`F-12` Proof)**:
  - Every `ABANDONED_FENCED`, `EXPIRED`, or `CANCELLED` mutation records `release_epoch = current_epoch` while holding `FOR SHARE` on `flash_sale_campaigns`.
  - `flash_sale_release.lua` validates `tonumber(redis.call('HGET', KEYS[1], 'epoch')) == tonumber(ARGV[3])` (`release_epoch`) and clamps `new_stock = math.min(allocated_quota, current_stock + add_qty)`.
  - If a Redis rebuild (`TX_REBUILDER_FENCE_AND_SNAPSHOT`) occurs first and advances `current_epoch` to `E + 1`, the Rebuilder's snapshot (`allocated_quota - SUM(active_claims)`) **already restores all freed stock from epochs `<= E`** and marks all `stock_returned_to_redis = FALSE` rows as `TRUE` inside the same `FOR UPDATE` transaction! Any in-flight RPC calling `flash_sale_release.lua` with `release_epoch = E < E + 1` is rejected by Redis Lua (`return -2`).

### 2. Sleep-Free `REBUILDING_GATE` Exclusive Lock & Zombie Termination Protocol (`F-11` Fix)
When `Promotion Service` detects a Redis restart/failover or missing/mismatched epoch:
1. **Step R0 (Active Zombie Backend Termination)**: Terminate any stalled backend holding a lock on `flash_sale_campaigns` for `> 3 seconds`:
   ```sql
   SELECT pg_terminate_backend(l.pid)
   FROM pg_locks l
   JOIN pg_stat_activity a ON a.pid = l.pid
   WHERE l.relation = 'flash_sale_campaigns'::regclass
     AND l.granted = TRUE
     AND a.pid <> pg_backend_pid()
     AND (NOW() - a.xact_start) > INTERVAL '3 seconds';
   ```
2. **Step R1 (`TX_REBUILDER_FENCE_AND_SNAPSHOT` — Exclusive `FOR UPDATE` Lock + Snapshot in One DB TX)**:
   - Execute `UPDATE flash_sale_campaigns SET status = 'REBUILDING_GATE', current_epoch = current_epoch + 1 WHERE campaign_id = :id RETURNING current_epoch`.
   - Because `UPDATE` acquires an exclusive `FOR UPDATE` lock on `flash_sale_campaigns` that conflicts with `FOR SHARE`, PostgreSQL's lock manager **blocks Step R1 until 100% of open `TX_WRITER`, `TX_RECONCILER`, and `TX_EXPIRE_OR_CANCEL` transactions holding `FOR SHARE` have committed or rolled back**, and blocks any new `FOR SHARE` locker until Step R1 commits!
   - Inside the **same transaction**, mark all prior `EXPIRED`/`CANCELLED`/`ABANDONED_FENCED` rows (`stock_returned_to_redis = TRUE`), reconcile `flash_sale_items.claimed_count`, and read the authoritative `remaining_stock` and active `buyers` map.
3. **Step R2 & R3 (Redis Reconstruction & Activation)**:
   - Write the snapshot and `epoch = :newEpoch` into Redis while `status = 'REBUILDING_GATE'` prevents any DB mutations, then flip Redis and `flash_sale_campaigns.status` back to `'ACTIVE'`.

---

## `CH-02`: Orthogonal Order & Payment State Machines (Provider Facts vs. Internal State)

- **Status:** `PROPOSED` (Adversarially Verified in `M0.2.2` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0004`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0004-hybrid-order-fulfillment-saga-orchestration.md)

### 1. Strict Separation of Provider-Reported Facts vs. Internal State (`F-04` Correction)
A financial ledger must **never fabricate timestamps**. If an external provider sends only a `payment.captured` webhook (either because it is a one-step direct capture method or because the `payment.authorized` webhook was dropped/delayed), `payment_attempts` sets **only** `provider_captured_at = webhook.occurred_at` and leaves `provider_authorized_at = NULL` until an actual `payment.authorized` event is received.

```mermaid
stateDiagram-v2
    [*] --> INITIATED : CreatePaymentAttempt
    INITIATED --> AUTHORIZED : webhook payment.authorized (sets provider_authorized_at)
    INITIATED --> CAPTURED : webhook payment.captured (sets provider_captured_at; provider_authorized_at stays NULL)
    INITIATED --> FAILED : webhook payment.failed / timeout
    AUTHORIZED --> CAPTURE_PENDING : Saga issues CapturePayment
    AUTHORIZED --> VOID_PENDING : Saga issues VoidPayment (Order expired/cancelled)
    CAPTURE_PENDING --> CAPTURED : webhook payment.captured
    CAPTURE_PENDING --> FAILED : webhook payment.capture_failed
    VOID_PENDING --> VOIDED : webhook payment.voided
    VOID_PENDING --> REFUND_PENDING : Late webhook payment.captured beat Void -> refund_requests -> Auto-Refund
    VOIDED --> REFUND_PENDING : Late webhook payment.captured after Void -> refund_requests -> Auto-Refund
    CAPTURED --> REFUND_PENDING : Saga issues RefundPayment (late payment or return)
    REFUND_PENDING --> Partially_Or_Fully_Refunded : webhook payment.refunded
```

#### 1.1 Corrected `payment_attempts`, `payment_webhook_logs` & `refund_requests` Schema (`payment_db`)
```sql
CREATE TABLE payment_webhook_logs (
    provider_event_id       VARCHAR(128) PRIMARY KEY,
    attempt_id              UUID NOT NULL,
    event_type              VARCHAR(64) NOT NULL,
    provider_occurred_at    TIMESTAMPTZ NOT NULL,
    raw_payload             JSONB NOT NULL,
    processing_outcome      VARCHAR(64) NOT NULL,   -- 'APPLIED', 'NOOP_DUPLICATE', 'NOOP_OUT_OF_ORDER', 'TRIGGERED_COMPENSATION'
    received_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE refund_requests (
    refund_id               UUID PRIMARY KEY,
    attempt_id              UUID NOT NULL REFERENCES payment_attempts(attempt_id),
    order_id                UUID NOT NULL,
    reason_code             VARCHAR(64) NOT NULL,   -- 'LATE_CAPTURE_AFTER_EXPIRY', 'LATE_CAPTURE_AFTER_VOID', 'CUSTOMER_REFUND'
    refund_idempotency_key  VARCHAR(128) NOT NULL UNIQUE,
    amount                  NUMERIC(19, 4) NOT NULL CHECK (amount > 0),
    status                  VARCHAR(32) NOT NULL CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED')),
    provider_refunded_at    TIMESTAMPTZ NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_attempt_refund_reason UNIQUE (attempt_id, reason_code)
);
```

### 2. Exhaustive Webhook & Command Transition Matrix (Including Missing & Contradictory Webhooks)

All three mutations (`INSERT INTO payment_webhook_logs`, `UPDATE payment_attempts`, and `INSERT INTO outbox_messages` / `refund_requests`) execute in **one local PostgreSQL transaction**:

| Current `PaymentAttempt.status` | Incoming Provider Webhook / Saga Command | Next `status` | Provider Fact Columns Updated | Outbox / Compensation Action (Same DB TX) |
| :--- | :--- | :--- | :--- | :--- |
| *Any State* | Any webhook whose `provider_event_id` already exists in `payment_webhook_logs` | *Unchanged* | None | `NOOP_DUPLICATE_EVENT_ID` (Return `200 OK`) |
| `INITIATED` | `webhook: payment.authorized` | `AUTHORIZED` | `provider_authorized_at = evt.ts` | Emit `PaymentAuthorized` |
| `INITIATED` | `webhook: payment.captured` *(Direct Capture or Missing Auth Webhook)* | `CAPTURED` | `provider_captured_at = evt.ts` *(Notice: `provider_authorized_at` stays `NULL`!)* | Emit `PaymentCaptured` |
| `INITIATED` | `webhook: payment.failed` | `FAILED` | `provider_failed_at = evt.ts` | Emit `PaymentAttemptFailed` |
| `AUTHORIZED` | `webhook: payment.authorized` *(Duplicate Auth with new event ID)* | `AUTHORIZED` | `provider_authorized_at = COALESCE(provider_authorized_at, evt.ts)` | `NOOP_ALREADY_AUTHORIZED` |
| `AUTHORIZED` | `Command: CapturePayment` | `CAPTURE_PENDING` | None | Dispatch capture to provider (`idempotency_key = attempt_id || ':capture'`) |
| `AUTHORIZED` | `Command: VoidPayment` *(Order Expired/Cancelled)* | `VOID_PENDING` | None | Dispatch void to provider (`idempotency_key = attempt_id || ':void'`) |
| `CAPTURED` | `webhook: payment.authorized` *(Out-of-Order Late Auth Webhook)* | `CAPTURED` *(Unchanged)* | `provider_authorized_at = COALESCE(provider_authorized_at, evt.ts)` | `NOOP_OUT_OF_ORDER_FACT_RECORDED` (Zero Outbox events emitted) |
| `CAPTURED` | `webhook: payment.captured` *(Duplicate Capture with new event ID)* | `CAPTURED` *(Unchanged)* | None | `NOOP_ALREADY_CAPTURED` |
| `CAPTURED` | `webhook: payment.failed` *(Contradictory Failure After Capture)* | `CAPTURED` *(Unchanged)* | Log anomaly in `payment_webhook_logs` | Emit `PaymentAnomalyDetected` alert; never downgrade `CAPTURED` to `FAILED`! |
| `VOID_PENDING` or `VOIDED` | `webhook: payment.captured` *(Contradictory Late Capture Beat Void!)* | `REFUND_PENDING` | `provider_captured_at = evt.ts` | Insert `refund_requests (reason='LATE_CAPTURE_AFTER_VOID') ON CONFLICT DO NOTHING` + Emit `PaymentAutoRefundInitiated` |
| `FAILED` | `webhook: payment.captured` *(Contradictory Capture After Failure)* | `CAPTURED` (if `Order` still `AWAITING_PAYMENT`) or `REFUND_PENDING` (if `Order` expired/paid by another attempt) | `provider_captured_at = evt.ts` | Evaluated against `Order` state; if `Order` already has another captured attempt or is `EXPIRED`, auto-refund via `refund_requests`! |

---

## `CH-03`: Class B Idempotency — Stale Worker Socket Analysis & Authoritative vs. Eventual `NOT_FOUND`

- **Status:** `PROPOSED` (Adversarially Verified in `M0.2.2` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0003`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0003-transactional-outbox-and-inbox-idempotency.md)

### 1. Adversarial Analysis: Can a Stale Worker Still Invoke an External Provider After Losing Its Lease? (`F-06`)
**Question**: Suppose Worker 1 (`lease_generation = 1`) acquires `idempotency_records` (`lease_expires_at = T + 30s`), prepares an HTTP request to an external provider, and freezes due to a `35s` JVM/CLR GC pause right before `socket.write()`. At $T + 31\text{s}$, Worker 2 steals the lease (`lease_generation = 2`). At $T + 35\text{s}$, Worker 1 unfreezes and flushes its TCP socket. **Does our local database `lease_generation` prevent Worker 1's packet from reaching the external provider?**
- **Honest Engineering Answer**: **NO.** No database lock or fencing token inside `Service A` can stop a paused OS thread inside `Service A` from transmitting an already-prepared TCP packet to an external system that does not check `Service A`'s fencing token!
- **How Correctness Is Guaranteed Across Both Layers**:
  1. **Layer 1 — Downstream Provider Idempotency / Fencing**:
     - Both Worker 1 (`lease_gen = 1`) and Worker 2 (`lease_gen = 2`) MUST pass the **exact same immutable `downstream_operation_id`** (assigned at `lease_generation = 1` before any external call) to the downstream provider.
     - For **Redis Lua** (which we control): We pass `ARGV[5] = lease_generation` into the Lua script, and Redis records `max_seen_lease_gen` per `claim_id`—so Redis **actively rejects** Worker 1's stale `lease_gen = 1` packet at the target resource!
     - For **External HTTP Payment Providers**: The provider deduplicates Worker 1 and Worker 2 using `Idempotency-Key: <downstream_operation_id>`.
  2. **Layer 2 — Local Database Fencing (`WHERE lease_generation = :expectedGen`)**:
     - When Worker 1 (`lease_gen = 1`) receives the response from its late TCP call and tries to `UPDATE idempotency_records ... WHERE lease_generation = 1`, PostgreSQL updates **`0` rows**, preventing Worker 1 from corrupting our local database or emitting duplicate Outbox events.

### 2. Authoritative vs. Eventually Consistent `NOT_FOUND` During `RECONCILING`

```mermaid
stateDiagram-v2
    [*] --> STARTED : Worker 1 inserts (lease_gen = 1, downstream_operation_id = UUID_1)
    STARTED --> COMPLETED_SUCCESS : Worker 1 commits response (WHERE lease_generation = 1)
    STARTED --> COMPLETED_RETRYABLE_ERROR : Transient 5xx/timeout before commit -> safe retry
    STARTED --> COMPLETED_TERMINAL_ERROR : Deterministic 4xx -> cached terminal error
    STARTED --> RECONCILING : Lease expired -> Worker 2 claims (lease_gen = 2, status = RECONCILING)
    RECONCILING --> COMPLETED_SUCCESS : Downstream query by UUID_1 shows SUCCEEDED
    RECONCILING --> COMPLETED_RETRYABLE_ERROR : Downstream query by UUID_1 shows FAILED
    RECONCILING --> STARTED : Type I Authoritative NOT_FOUND -> safe to execute with same UUID_1
    RECONCILING --> MANUAL_INTERVENTION_REQUIRED : Type II Eventually Consistent NOT_FOUND unresolved after 15m
```

When Worker 2 (`lease_generation > 1`) enters `RECONCILING` and queries the downstream system by `downstream_operation_id`:

| Downstream System Type | Meaning of `NOT_FOUND` Response During `RECONCILING` | Allowed Recovery Action |
| :--- | :--- | :--- |
| **Type I: Strongly Consistent Read-After-Write + Idempotent on `downstream_operation_id`** *(e.g., Redis primary on same epoch, Payment Simulator / Stripe API with `Idempotency-Key`)* | Either the prior packet never reached the downstream system, OR if a paused Worker 1 packet arrives later, the downstream system will deduplicate it using `downstream_operation_id`. | Safe to transition `RECONCILING -> STARTED` and invoke downstream using the **same `downstream_operation_id`**. |
| **Type II: Eventually Consistent Read Endpoint OR Non-Idempotent Downstream** | **`NOT_FOUND` is NOT authoritative!** The prior call may already be queued/committed on the provider's write node but not yet visible on its read replica. Re-invoking a non-idempotent call will double-execute! | **FORBIDDEN to re-invoke the external side effect!** Record must remain in `RECONCILING` (polling with exponential backoff `2s, 4s, 8s...`). If unresolved after `max_reconcile_duration` (`15m`), transition to **`MANUAL_INTERVENTION_REQUIRED`** (`503 Service Unavailable`, emitting `IdempotencyReconciliationStuckAlert` for Ops). |

---

## `CH-04`: Dedicated Shard Dispatcher with Two-Stage `INITIALIZING -> ACTIVE` Ownership & Head-Event Cycle

- **Status:** `PROPOSED` (Redesigned & Logically Verified in `M0.2.4` — Pending Final Sign-Off)
- **Related ADRs:** [`ADR-0003`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0003-transactional-outbox-and-inbox-idempotency.md), [`ADR-0010`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0010-event-contracts-json-schema-and-kafka-kraft.md)
- **Detailed Concurrency Reports:** [`M0_2_3_CONCURRENCY_CORRECTIONS.md#3-ch-04-redesign`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_3_CONCURRENCY_CORRECTIONS.md), [`M0_2_4_FINAL_FENCING_REVIEW.md#3-ch-04`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md)

### 1. Eliminating Stale Publishers (`[v1, v2, v1]`), Batch-Crash Replays (`[v1, v2, v1, v2]`), and the `initTransactions()` Ownership Race (`F-13`, `F-14`, `F-16`)

As proven in [`M0_2_4_FINAL_FENCING_REVIEW.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md):
1. **Dedicated Shard Dispatcher (`StatefulSet` Ordinal Pinning + Single Worker Thread per Shard)**:
   - Outbox Relay workers run in a dedicated Shard Dispatcher (not inside all $N$ stateless HTTP API pods). Each `shard_id` (`0..15`) is owned by a single dedicated thread that calls `initTransactions()` **once** during shard acquisition and **never** calls `initTransactions()` while in `ACTIVE` state.
2. **Two-Stage Shard Lease State Machine (`INITIALIZING -> ACTIVE`)**:
   - **Step 1 (`ACQUIRE_INITIALIZING`)**: Terminates any expired prior backend session (`pg_terminate_backend(owner_backend_pid)`) and sets `status = 'INITIALIZING'`, `fencing_epoch = fencing_epoch + 1`, `initializing_deadline = NOW() + 35s`. **Zero outbox rows may be read or claimed while `status = 'INITIALIZING'`!**
   - **Step 2 (`BROKER_INIT_TRANSACTIONS` with `15s` Monotonic Watchdog)**: Checks `(System.nanoTime() - localStartNanos) <= 15s` and calls `txProducer.initTransactions()` (`default.api.timeout.ms = 15s`, `35s` takeover delay `> 2x` local cutoff). If a thread paused `> 35s` before `initTransactions()`, the `15s` monotonic pre-check aborts in user space before touching Kafka.
   - **Step 3 (`ACTIVATE_SHARD_CAS`)**: After `initTransactions()` returns, executes `UPDATE outbox_relay_shards SET status = 'ACTIVE', broker_fenced_epoch = :myEpoch WHERE shard_id = :shardId AND owner_pod = :podId AND fencing_epoch = :myEpoch AND status = 'INITIALIZING'`. If `0` rows are updated (a newer owner took over), the producer is immediately closed without ever reading or publishing a single row from `outbox_messages`.
   - **Self-Healing `ProducerFencedException` Recovery**: Once `ACTIVE`, a worker never calls `initTransactions()`. If an `ACTIVE` owner catches `ProducerFencedException` while still owning the DB shard, it re-enters `acquire_and_initialize_shard()` (`fencing_epoch + 1`), re-runs `initTransactions()` (`ProducerEpoch++`), and resumes seamlessly.
3. **Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)**:
   - Each `Phase 1` batch claims **at most ONE event (the lowest unpublished `aggregate_version`) per `aggregate_id`** across up to `100` distinct aggregates in that shard (`status = 'ACTIVE'`). Version `v+1` is never sent to Kafka until version `v` is committed in Kafka and marked `processed_at = NOW()` in PostgreSQL.

#### 1.1 Updated `outbox_relay_shards` & `outbox_messages` Schema
```sql
CREATE TABLE outbox_relay_shards (
    shard_id              INTEGER PRIMARY KEY CHECK (shard_id BETWEEN 0 AND 15),
    status                VARCHAR(24)  NOT NULL DEFAULT 'IDLE'
                          CHECK (status IN ('IDLE', 'INITIALIZING', 'ACTIVE')),
    owner_pod             VARCHAR(128) NULL,
    owner_backend_pid     INTEGER      NULL,
    fencing_epoch         BIGINT       NOT NULL DEFAULT 0,
    broker_fenced_epoch   BIGINT       NOT NULL DEFAULT 0,
    initializing_deadline TIMESTAMPTZ  NULL,
    lease_until           TIMESTAMPTZ  NOT NULL DEFAULT '-infinity',
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE outbox_messages (
    outbox_sequence       BIGSERIAL UNIQUE NOT NULL,
    event_id              UUID PRIMARY KEY,
    shard_id              INTEGER      NOT NULL CHECK (shard_id BETWEEN 0 AND 15),
    aggregate_type        VARCHAR(64)  NOT NULL,
    aggregate_id          VARCHAR(128) NOT NULL,
    aggregate_version     BIGINT       NOT NULL CHECK (aggregate_version >= 1),
    event_type            VARCHAR(128) NOT NULL,
    topic                 VARCHAR(128) NOT NULL,
    partition_key         VARCHAR(128) NOT NULL,
    payload               JSONB        NOT NULL,
    headers               JSONB        NOT NULL,
    claimed_fencing_epoch BIGINT       NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    processed_at          TIMESTAMPTZ  NULL,
    retry_count           INTEGER      NOT NULL DEFAULT 0,
    last_error            TEXT         NULL,
    CONSTRAINT uq_outbox_aggregate_version UNIQUE (aggregate_type, aggregate_id, aggregate_version, event_type)
);

CREATE INDEX idx_outbox_shard_head
    ON outbox_messages (shard_id, aggregate_id, aggregate_version ASC, outbox_sequence ASC)
    WHERE processed_at IS NULL;
```

#### 1.2 Exact 3-Phase Shard-Fenced Outbox Relay SQL (`status = 'ACTIVE'` Required)
- **Step 0 (`INITIALIZING -> initTransactions() -> ACTIVE` Two-Stage Handshake)**: See full SQL and pseudocode in [`M0_2_4_FINAL_FENCING_REVIEW.md#332`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_4_FINAL_FENCING_REVIEW.md).
- **Phase 1 — Renew `ACTIVE` Lease & Claim Only the Head Event (`DISTINCT ON (aggregate_id)`) Per Aggregate (`< 2ms` TX)**:
  ```sql
  WITH renewed_shard AS (
      UPDATE outbox_relay_shards
      SET lease_until = NOW() + INTERVAL '30 seconds',
          updated_at = NOW()
      WHERE shard_id = :shardId
        AND status = 'ACTIVE'
        AND owner_pod = :podId
        AND fencing_epoch = :myEpoch
        AND broker_fenced_epoch = :myEpoch
        AND lease_until > NOW()
      RETURNING shard_id, fencing_epoch
  ),
  head_per_aggregate AS (
      SELECT DISTINCT ON (m.aggregate_id)
             m.event_id, m.aggregate_id, m.aggregate_version, m.outbox_sequence
      FROM outbox_messages m
      JOIN renewed_shard rs ON rs.shard_id = m.shard_id
      WHERE m.processed_at IS NULL
      ORDER BY m.aggregate_id, m.aggregate_version ASC, m.outbox_sequence ASC
      LIMIT 100
  )
  UPDATE outbox_messages m
  SET claimed_fencing_epoch = :myEpoch
  FROM head_per_aggregate h
  WHERE m.event_id = h.event_id
  RETURNING m.event_id, m.aggregate_type, m.aggregate_id, m.aggregate_version,
            m.event_type, m.topic, m.partition_key, m.payload, m.headers, m.claimed_fencing_epoch;
  ```
- **Phase 2 — Transactional Kafka Publish (`beginTransaction()` -> `send()` -> `commitTransaction()`)**:
  - `initTransactions()` is **never** called in Phase 2. Any late packet from a paused prior `ACTIVE` worker is rejected by the Kafka broker with `ProducerFencedException`.
- **Phase 3 — Short DB Completion Transaction (`< 2ms`)**:
  ```sql
  UPDATE outbox_messages m
  SET processed_at = NOW()
  FROM outbox_relay_shards s
  WHERE m.event_id = ANY(:eventIds)
    AND m.shard_id = s.shard_id
    AND s.shard_id = :shardId
    AND s.status = 'ACTIVE'
    AND s.owner_pod = :podId
    AND s.fencing_epoch = :myEpoch;
  ```
- **Defense-in-Depth Consumer Contract**:
  - Consumers configure `isolation.level = read_committed`, deduplicate `event_id` in `inbox_messages (event_id, consumer_group)`, ignore `incoming.aggregate_version <= aggregate.last_applied_version` as an idempotent no-op, apply `== last_applied_version + 1`, and route `> last_applied_version + 1` to `.retry` (`SEQUENCE_GAP_DETECTED`).

---

## `CH-05`: OIDC / RFC 9068 Access Token Validation & Privilege Escalation Prevention

- **Status:** `PROPOSED` (Adversarially Verified in `M0.2.2` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0006`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md)

### 1. Eliminating Cross-Service Role Union Privilege Escalation (`F-08` Fix)
In `M0.2.1`, we wrote `roles = union(jwt.roles, jwt.realm_access.roles, jwt.resource_access["commerce-api"].roles)`. Under adversarial review, a flat union without principal-type separation creates two escalation risks:
1. If an M2M service client in Keycloak accidentally inherits a default realm role (e.g., `CUSTOMER`), a background service token could invoke customer-only endpoints.
2. If Service X checks `resource_access` without scoping to its own `service_id`, a client role meant only for `notification-service` could be accepted by `payment-service`.

#### 1.1 Corrected RFC 9068 Claim Validation & Principal Separation Rules
1. **Mandatory RFC 9068 Header & Claim Checks**:
   - `alg`: Must be `"RS256"` (allowlist of asymmetric algorithms; `"none"` and `"HS256"` rejected).
   - `typ`: Must be `"at+jwt"` or `"JWT"`. (Any OIDC `id_token` has `aud = "commerce-web-spa"` and lacks `"commerce-api"`, and is rejected with `401 Unauthorized`).
   - `iss`: Exact string match against `AUTH_ISSUER_URI`.
   - `aud`: Must contain `"commerce-api"` (for external routes) OR the target service's exact identifier (e.g., `"inventory-service"` for internal M2M routes).
   - `exp`, `iat`, `nbf`: Validated with `<= 30s` clock skew.
   - `sub` & `jti`: Must be non-empty strings.
2. **Strict Principal-Type Separation (`HUMAN_PRINCIPAL` vs. `SERVICE_PRINCIPAL`)**:
   - If `jwt.client_id` / `jwt.azp` is in the registered M2M service client list (or `jwt.sub` starts with `"service-account-"`):
     - Classify principal as **`SERVICE_PRINCIPAL`**.
     - **Strip and ignore** any human roles (`CUSTOMER`, `ADMIN_MERCHANT`, `ADMIN_OPS`) even if present in the token!
     - Authorize **exclusively** via explicit `(resolved_client_id, SCOPE_*, SERVICE_ROLE_*)` allowlist rules on internal endpoints.
   - If principal is a **`HUMAN_PRINCIPAL`**:
     - Extract human realm roles only from the explicit allowlist `{"CUSTOMER", "ADMIN_MERCHANT", "ADMIN_OPS"}` present in `jwt.roles` or `jwt.realm_access.roles`.

---

## `CH-06`: `pgvector` Storage vs. ANN Index Limits & Benchmark Target Classification

- **Status:** `PROPOSED` (Adversarially Verified in `M0.2.2` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0008`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md)

### 1. Verified `pgvector` Physical Limits vs. Empirical Benchmark Targets (`F-09` Fix)

| Property | Value | Verification Classification |
| :--- | :--- | :--- |
| Max dimensions stored in unindexed `vector` or `halfvec` table column | `16,000` dimensions | **`VERIFIED`** (`pgvector` source constant `VECTOR_MAX_DIM`) |
| Max dimensions indexed by HNSW / IVFFlat for FP32 `vector` (`vector_cosine_ops`, `vector_l2_ops`, `vector_ip_ops`) | **`2,000` dimensions** | **`VERIFIED`** (PostgreSQL 8 KB index page limit; `3072d` `vector` HNSW fails with `ERROR: column cannot have more than 2000 dimensions for hnsw index`) |
| Max dimensions indexed by HNSW / IVFFlat for FP16 `halfvec` (`halfvec_cosine_ops`, `halfvec_l2_ops`, `halfvec_ip_ops`) | **`4,000` dimensions** | **`VERIFIED`** (`pgvector` `HALFVEC_MAX_DIM` for HNSW/IVFFlat; supports `3072d` natively) |
| Storage size reduction of `halfvec(D)` (2 bytes/float) vs. `vector(D)` (4 bytes/float) per tuple | `50%` vector payload size reduction | **`VERIFIED`** (IEEE 754 binary16 vs. binary32 arithmetic) |
| RAG `Recall@10 >= 0.95` and query latency `p95 < 50ms` for `halfvec` vs. `vector` on product catalog | Target SLO: `Recall@10 >= 0.95`, `p95 < 50ms` | **`NEEDS_EVIDENCE`** *(Empirical Benchmark Target — depends on catalog distribution and HNSW `m` / `ef_search`; to be measured in `M5/M7`, never claimed as an a priori guarantee)* |

---

## `CH-07`: Observability Trace Continuity & Fail-Closed Production Fault Injection Guard

- **Status:** `PROPOSED` (Adversarially Verified in `M0.2.2` — Pending Final Sign-Off)
- **Related ADR:** [`ADR-0011`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0011-observability-opentelemetry-and-lgtm-stack.md)

### 1. Fail-Closed Production Startup & Triple-Gated Fault Injection (`F-10` Fix)
To guarantee that fault injection fails closed even if an operator misconfigures a ConfigMap in production:
1. **Gate 1 — Fail-Closed Startup Panic on Misconfiguration**:
   - At application startup (in Java `ApplicationRunner`, .NET `IHostedService`, and Python FastAPI `lifespan`), execute:
     ```text
     IF (ENVIRONMENT == "production" OR PRODUCTION_LOCK == "true") AND FAULT_INJECTION_ENABLED == true:
         LOG FATAL "SECURITY_VIOLATION: FAULT_INJECTION_ENABLED cannot be true when ENVIRONMENT=production"
         EXIT_PROCESS(1)
     ```
2. **Gate 2 — Absent DI Registration when `FAULT_INJECTION_ENABLED == false`**:
   - When `FAULT_INJECTION_ENABLED == false` (the default), the `FaultInjectionFilter` / interceptor bean is not instantiated or registered in the HTTP/Kafka pipeline, and the API Gateway unconditionally strips `X-Fault-Profile-Id` and removes `fault.profile_id` from W3C `baggage`.
3. **Gate 3 — Authorization + Server-Side Profile + Target Allowlist when `FAULT_INJECTION_ENABLED == true` (Non-Prod Chaos Mode)**:
   - Requires verified `HUMAN_PRINCIPAL` JWT with `ROLE_ADMIN_OPS` and `SCOPE_chaos:inject` (W3C `baggage` is never trusted for authorization).
   - Looks up `profile_id` in immutable server-side `fault-profiles.yaml`. Unknown `profile_id` returns `400 Bad Request (UNKNOWN_FAULT_PROFILE)`.
   - Verifies `current_service_name \in profile.allowedTargetServices` and `request_route \in profile.allowedTargetOperations`. Non-matching targets return `403 Forbidden (FAULT_TARGET_NOT_ALLOWED)`.
   - Emits a mandatory structured `WARN` audit log (`CHAOS_FAULT_PROFILE_ACTIVATED`).

### 2. Reproducible Test Specifications for `CH-01` through `CH-07` (`To Be Executed in M1–M7`)

> [!NOTE]
> Because `M0.2.3` is an architecture verification milestone with zero application code implemented yet, **none of the runtime tests below have been executed yet (`Status: NEEDS_EVIDENCE`)**. They are specified here as mandatory acceptance gates for `M1–M7`:

| Test ID | Challenge | Reproducible Test Specification | Expected Verification Result |
| :--- | :--- | :--- | :--- |
| `SPEC-CH01-T1` | `CH-01` | Use `CountDownLatch` in Testcontainers (`Postgres + Redis`): pause Writer `W1` before `TX_WRITER` commits; run Reconciler `R1` (`ABANDONED_FENCED`); release `W1`. | `W1` sees `0` rows inserted from `ON CONFLICT DO NOTHING`, queries status `'ABANDONED_FENCED'`, rolls back `TX_WRITER`, and Redis stock is incremented by `R1` **exactly once**. |
| `SPEC-CH01-T2` | `CH-01` | Expire a claim (`stock_returned_to_redis = TRUE`), delete `released_claims` key in Redis (simulating TTL expiry), and replay `FlashSaleClaimReleased` Kafka event. | Worker checks PostgreSQL `WHERE stock_returned_to_redis = FALSE`, updates `0` rows, and skips calling `flash_sale_release.lua` (`0` double-restock). |
| `SPEC-CH01-T3` | `CH-01` | Hold `SELECT ... FROM flash_sale_campaigns WHERE campaign_id = :id AND current_epoch = 1 FOR SHARE` open for `6s` while starting `TX_REBUILDER_FENCE_AND_SNAPSHOT`. | `idle_in_transaction_session_timeout = 3s` / `Step R0` (`pg_terminate_backend`) terminates the stalled backend, `TX_REBUILDER` bumps `current_epoch = 2`, and any late single-CTE Writer carrying `redisClaimEpoch = 1` matches `0` rows in `campaign_guard` and aborts. |
| `SPEC-CH01-T4` | `CH-01` | Expire claim `C1` in `epoch = 1` (`release_epoch = 1`), run `TX_REBUILDER_FENCE_AND_SNAPSHOT` (`current_epoch = 2`), and invoke `flash_sale_release.lua` with `ARGV[3] = 1`. | Redis Lua returns `-2` (`STALE_EPOCH`) and does not increment `epoch = 2` stock above `allocated_quota - claimed_count`. |
| `SPEC-CH01-T5` | `CH-01` | Attempt (a) `UPDATE flash_sale_claims SET stock_returned_to_redis = TRUE` with stale `release_epoch < current_epoch`, (b) `UPDATE flash_sale_claims SET status = 'ORDER_MATERIALIZED'` during `REBUILDING_GATE`, and (c) `UPDATE flash_sale_items` during `REBUILDING_GATE`. | All three mutations are blocked by `campaign_guard` and rejected by `trg_enforce_claims_campaign_lock` / `trg_enforce_items_campaign_lock` (`SQLSTATE P0001`/`P0003`). |
| `SPEC-CH02-T1` | `CH-02` | Send direct `webhook: payment.captured` to `INITIATED` `PaymentAttempt`. | `status` becomes `CAPTURED`, `provider_captured_at` is set, and `provider_authorized_at` remains `NULL` (not fabricated). |
| `SPEC-CH02-T2` | `CH-02` | Transition `PaymentAttempt` to `VOIDED`, then deliver two duplicate `payment.captured` webhooks (`W1`, `W2`). | Attempt transitions to `REFUND_PENDING`, `refund_requests` inserts `1` row (`UNIQUE (attempt_id, reason_code)`), and gateway refund is invoked **once**. |
| `SPEC-CH03-T1` | `CH-03` | Simulate Worker 1 (`lease_gen = 1`) freezing before external call, Worker 2 (`lease_gen = 2`) completing via `RECONCILING`, and Worker 1 waking up to send its external call and update DB. | Downstream deduplicates on `downstream_operation_id`; Worker 1's local DB update (`WHERE lease_generation = 1`) updates `0` rows. |
| `SPEC-CH04-T1` | `CH-04` | Insert 10 sequential events (`v=1..10`) for `orderId = O1` while running 4 concurrent Outbox Relay threads using the `outbox_relay_shards` + `DISTINCT ON (aggregate_id)` query. | Each cycle claims only the lowest unpublished `aggregate_version` for `O1`; consumer receives strict `[1..10]` order. |
| `SPEC-CH04-T2` | `CH-04` | Relay A (`shard_id = 3`) begins a Kafka transaction (`transactional.id = "...-shard-3"`), sends `O1:v1`, and pauses before `commitTransaction()`. Relay B steals `shard_id = 3`, calls `initTransactions()`, and publishes `O1:v1` and `O1:v2`. Resume Relay A and call `commitTransaction()`. | Kafka broker rejects Relay A with `ProducerFencedException`; `READ_COMMITTED` consumer receives strictly `[O1:v1, O1:v2]`. |
| `SPEC-CH04-T3` | `CH-04` | Insert `O1:v1` and `O1:v2` into `outbox_messages`. Crash Relay A immediately after `commitTransaction()` for `O1:v1` before Phase 3 updates PostgreSQL. Run Relay B for 2 cycles. | `O1:v2` was never sent by Relay A; Relay B publishes `O1:v1` in Cycle 1 and `O1:v2` in Cycle 2 (`[v1, v1, v2]` in Kafka), and Consumer Inbox applies `v1` once and `v2` once. |
| `SPEC-CH04-T4` | `CH-04` | Relay A acquires `fencing_epoch = 10` (`status = 'INITIALIZING'`) and pauses `> 35s` before `initTransactions()`. Relay B acquires `fencing_epoch = 11`, activates (`status = 'ACTIVE'`), and publishes `O1:v1`. Resume Relay A. | (1) `15s` monotonic pre-check aborts Relay A before `initTransactions()`; (2) even if `initTransactions()` is forced in white-box test, Relay A fails Step 3 `ACTIVATE_SHARD_CAS` (`0` rows, `0` events read/sent) and Relay B self-heals (`fencing_epoch = 12`) and publishes `O1:v2`. |
| `SPEC-CH05-T1` | `CH-05` | Mint an M2M `client_credentials` token that maliciously includes `"roles": ["CUSTOMER", "ADMIN_OPS"]` in its payload, and call `POST /api/v1/orders` and `/api/v1/admin/products`. | Auth middleware classifies token as `SERVICE_PRINCIPAL`, strips human roles, and rejects both calls with `403 Forbidden`. |
| `SPEC-CH06-T1` | `CH-06` | Attempt `INSERT INTO embedding_index_generations (dimensions=3072, index_storage_type='VECTOR_FP32')` vs `index_storage_type='HALFVEC_FP16'`. | `VECTOR_FP32` at `3072d` is rejected by PostgreSQL `CHECK` constraint; `HALFVEC_FP16` succeeds and builds `USING hnsw ((embedding::halfvec(3072)) halfvec_cosine_ops)`. |
| `SPEC-CH07-T1` | `CH-07` | Start service with `ENVIRONMENT=production` and `FAULT_INJECTION_ENABLED=true`. | Process aborts startup immediately with `FatalSecurityConfigurationException` (`exitCode != 0`). |
| `SPEC-CH07-T2` | `CH-07` | In chaos mode (`ENVIRONMENT=chaos`, `FAULT_INJECTION_ENABLED=true`), send `X-Fault-Profile-Id: FP-PAY-TIMEOUT` with (a) `CUSTOMER` JWT (`403`), (b) `ADMIN_OPS` JWT to `product-service` (`403` target not allowlisted), and (c) unknown profile `FP-FAKE` (`400`). | All three unauthorized/invalid attempts fail closed and emit security warning logs. |
