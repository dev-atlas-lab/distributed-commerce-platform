# `M0.2.3` — Final Concurrency Corrections Report (`CH-01` & `CH-04`)

- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Milestone:** `M0.2.3 — Final Concurrency Corrections (CH-01 & CH-04)`
- **Baseline Commit Audited:** `d41e91c` (`origin/main`)
- **Date:** 2026-11-11
- **Status of Foundational Decisions (`Q1–Q7`):** **`ACCEPTED`** (Unchanged)
- **Status of `CH-01` & `CH-04`:** **`PROPOSED` (Redesigned & Logically Verified in `M0.2.3` — Pending Explicit Human Sign-Off)**
- **Runtime Execution Disclosure:** Because `M0.2.3` is a pre-implementation architecture milestone (`M0`), **zero runtime tests have been executed**. All verification items below explicitly distinguish **Logical/Mathematical Verification (`VERIFIED`)** from **Runtime Test Verification (`NEEDS_EVIDENCE` — scheduled for `M1–M7`)**.

---

## 1. Executive Summary of `M0.2.3` Findings & Classifications

| Finding ID | Challenge | Defect Identified in `d41e91c` (`M0.2.2`) | `M0.2.2` Audit Status | `M0.2.3` Architectural Redesign & Resolution | `M0.2.3` Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`F-11`** | **`CH-01`** | **False Epoch Fence & Fixed `5.5s` Sleep Fallacy**: `M0.2.2` relied on a lock-free `SELECT current_epoch` (`Step W1`), `statement_timeout = 5s`, and a fixed `5.5s` sleep in the Rebuilder. Because PostgreSQL `statement_timeout` applies to *individual SQL statements* (not the whole transaction), an old-epoch Writer (`epoch = 1`) could run `Step W1` (`1ms`), pause inside its open transaction for `10s` (GC pause / thread stall), outlive the `5.5s` sleep, and commit `flash_sale_claims` + `flash_sale_items` *after* Redis reconstruction started. | **`FAILED`** | Replaced lock-free `SELECT` and fixed sleep with **Lock-Serialized Single-Statement CTE Execution + `FOR SHARE` / `FOR UPDATE` Campaign Lock Barrier + Active Zombie Termination (`pg_terminate_backend`)**. Every Writer/Reconciler/Restock TX acquires `FOR SHARE` on `flash_sale_campaigns`; the Rebuilder acquires conflicting `FOR UPDATE` on `flash_sale_campaigns`, mathematically guaranteeing zero old-epoch transactions can remain open or commit after the rebuild boundary. | **`VERIFIED`** *(Logical)* / **`NEEDS_EVIDENCE`** *(Runtime `SPEC-CH01-T3`)* |
| **`F-12`** | **`CH-01`** | **Cross-Epoch Stock Return Inflation**: In `M0.2.2`, if a claim transitioned to `ABANDONED_FENCED`, `EXPIRED`, or `CANCELLED` in `epoch = 1` (`stock_returned_to_redis = FALSE`), and Redis crashed and rebuilt at `epoch = 2` (which computes `stock = allocated_quota - claimed_count`, *already* restoring that freed stock), a late release worker from `epoch = 1` calling `flash_sale_release.lua` would increment `epoch = 2` Redis stock a second time (`stock > allocated_quota`). | **`FAILED`** | Added `release_epoch BIGINT` to `flash_sale_claims` and required `flash_sale_release.lua` to validate `redis_epoch == ARGV[3] (release_epoch)`. During `TX_REBUILDER_FENCE_AND_SNAPSHOT`, holding `FOR UPDATE` on `flash_sale_campaigns` atomically marks all prior `stock_returned_to_redis = FALSE` rows as `TRUE` (`release_epoch < new_epoch`), since their freed stock is already baked into the `epoch = E + 1` snapshot. | **`VERIFIED`** *(Logical)* / **`NEEDS_EVIDENCE`** *(Runtime `SPEC-CH01-T4`)* |
| **`F-13`** | **`CH-04`** | **Stale Outbox Publisher Across Lease Expiry (`[v1, v2, v1]`)**: In `M0.2.2`, Relay A claims `O1:v1` (`30s` DB lease) and pauses `>30s` during Kafka publication; Relay B reclaims `O1` and publishes `v1` then `v2`; Relay A resumes and flushes `v1` over TCP. Neither a DB lease nor standard per-instance `enable.idempotence=true` prevents the Kafka broker from appending Relay A's late `v1` after `v2`. | **`FAILED`** | Introduced **Shard-Scoped Single-Writer Leases (`outbox_relay_shards`) + Deterministic Kafka `transactional.id` Broker-Enforced `ProducerEpoch` Fencing**. When Relay B claims `shard_id`, it calls `producer.initTransactions()` for `transactional.id = "<service>-outbox-shard-" + shard_id` *before* querying or publishing any rows. The Kafka broker bumps `ProducerEpoch` and rejects any resumed `ProduceRequest` / `EndTxnRequest` from paused Relay A with `ProducerFencedException`. | **`VERIFIED`** *(Logical)* / **`NEEDS_EVIDENCE`** *(Runtime `SPEC-CH04-T2`)* |
| **`F-14`** | **`CH-04`** | **Multi-Version Batch Crash After Kafka Ack Before DB Update (`[v1, v2, v1, v2]`)**: Even with broker fencing, if Relay A publishes *both* `O1:v1` and `O1:v2` in a single Phase 2 batch and crashes right after Kafka commit before Phase 3 DB completion, Relay B sees both `v1` and `v2` as `processed_at IS NULL` and re-publishes `[v1, v2]`, placing `v1` after `v2` in the Kafka log. | **`FAILED`** | Enforced **Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)**: each Relay cycle claims *at most one event (the lowest unpublished `aggregate_version`)* per `aggregate_id` across up to `100` distinct aggregates in the shard. `O1:v2` is **never sent to Kafka** until `O1:v1` is marked `processed_at = NOW()` in PostgreSQL—so a crash between Phase 2 and Phase 3 can only produce `[v1, v1, v2]` (monotonic non-decreasing versions), paired with Consumer Inbox & `aggregate_version <= last_applied_version` deduplication. | **`VERIFIED`** *(Logical)* / **`NEEDS_EVIDENCE`** *(Runtime `SPEC-CH04-T3`)* |

---

## 2. `CH-01` Redesign — Lock-Serialized Epoch Fencing & Sleep-Free Redis Rebuild

### 2.1 Why the `M0.2.2` Design (`5.5s` Sleep + `statement_timeout = 5s`) Failed (`F-11` Proof)
In `d41e91c`, `TX_WRITER` executed multiple statements in a transaction starting with a lock-free query:
```sql
SELECT current_epoch FROM flash_sale_campaigns
WHERE campaign_id = :campaignId AND current_epoch = :redisClaimEpoch;
```
Consider the following adversarial execution timeline under `M0.2.2`:
1. **$T = 0.000\text{s}$**: Writer $W_1$ (`redisClaimEpoch = 1`) begins `TX_WRITER` (`READ COMMITTED`) and executes `Step W1`. The `SELECT` completes in `0.4ms` and returns `current_epoch = 1`. Because it is a plain `SELECT`, PostgreSQL holds **zero row locks** on `flash_sale_campaigns` after the statement finishes.
2. **$T = 0.001\text{s}$**: Right before sending `Step W2` (`INSERT INTO flash_sale_claims`), the JVM/.NET application thread hosting $W_1$ stalls for `8.0 seconds` (e.g., stop-the-world GC pause, container CPU throttling, or network delay between client statements). Notice that **no SQL statement is currently running in PostgreSQL**, so `statement_timeout = 5s` is **never triggered**!
3. **$T = 0.500\text{s}$**: Redis suffers an un-fsynced restart. Rebuilder $R_{\text{rebuild}}$ updates `flash_sale_campaigns SET status = 'REBUILDING_GATE', current_epoch = 2` (which succeeds immediately because $W_1$ holds no lock!) and sleeps for `5.5 seconds` ($T = 0.5\text{s} \to 6.0\text{s}$).
4. **$T = 6.000\text{s}$**: Rebuilder $R_{\text{rebuild}}$ wakes up after `5.5s`, queries `SUM(quantity)` from `flash_sale_claims` (which does **not** include $W_1$), rebuilds Redis with `epoch = 2`, and flips the campaign back to `ACTIVE`.
5. **$T = 8.001\text{s}$**: Writer $W_1$ resumes from its `8.0s` application pause and sends `Step W2` (`INSERT INTO flash_sale_claims ... campaign_epoch = 1`), `Step W4` (`UPDATE flash_sale_items SET claimed_count = claimed_count + 1`), and `COMMIT`. Each statement takes `< 1ms` (well within `statement_timeout = 5s`) and **commits successfully**!
6. **Catastrophic Result in `M0.2.2`**: $W_1$'s `epoch = 1` claim committed **after** the `epoch = 2` Redis rebuild took its snapshot! Redis `epoch = 2` now has `1` more unit of stock than PostgreSQL's remaining quota, causing a **guaranteed oversell (or `Step W4` quota exhaustion failure for the last legitimate `epoch = 2` buyer)**.

---

### 2.2 The `M0.2.3` Solution: Lock-Serialized Epoch Barrier + Single-Statement CTE Mutations (Zero Fixed Sleep)

We eliminate the `M0.2.2` flaw through five reinforcing mechanisms:

#### 1. Strict Global PostgreSQL Lock Acquisition Order
Every transaction in `promotion_db` that touches Flash Sale state MUST acquire locks in the following strict topological hierarchy (preventing any circular lock wait / deadlock):
$$\text{1. } \texttt{flash\_sale\_campaigns} \longrightarrow \text{2. } \texttt{flash\_sale\_claims} \longrightarrow \text{3. } \texttt{flash\_sale\_items} \longrightarrow \text{4. } \texttt{outbox\_messages} \longrightarrow \text{5. } \texttt{idempotency\_records}$$

| Transaction Type | Lock Acquired on `flash_sale_campaigns` (Step 1) | Lock Compatibility with Concurrent Writers/Reconcilers | Lock Compatibility with `TX_REBUILDER` |
| :--- | :--- | :--- | :--- |
| **`TX_WRITER`** *(Persist Redis claim)* | `SELECT ... FOR SHARE` (`WHERE current_epoch = :epoch AND status = 'ACTIVE'`) | **Compatible** (`FOR SHARE` never blocks `FOR SHARE`) | **Mutually Exclusive** (Blocks `FOR UPDATE` and is blocked by `FOR UPDATE`) |
| **`TX_RECONCILER`** *(Fence expired Redis intent lease)* | `SELECT ... FOR SHARE` (`WHERE current_epoch = :epoch AND status = 'ACTIVE'`) | **Compatible** | **Mutually Exclusive** |
| **`TX_EXPIRE_OR_CANCEL`** *(Expire/Cancel committed claim)* | `SELECT ... FOR SHARE` (`WHERE status = 'ACTIVE'`) | **Compatible** | **Mutually Exclusive** |
| **`TX_REBUILDER_FENCE_AND_SNAPSHOT`** *(Bump epoch & read authoritative snapshot)* | `SELECT ... FOR UPDATE` (`UPDATE flash_sale_campaigns SET current_epoch = current_epoch + 1, status = 'REBUILDING_GATE'`) | **Mutually Exclusive** (Waits for all open `FOR SHARE` TXs to finish; blocks all new `FOR SHARE` TXs) | **Mutually Exclusive** |

#### 2. Single-Statement Data-Modifying CTE Execution (Eliminating Mid-Transaction Client Pauses)
Instead of executing `Step W1`, `Step W2`, `Step W4`, and `Step W5` as separate client-to-PostgreSQL round-trips where a JVM/.NET pause between statements leaves a transaction holding locks idle, each mutation (`TX_WRITER`, `TX_RECONCILER`, `TX_EXPIRE_OR_CANCEL`) executes as a **single atomic PostgreSQL Data-Modifying CTE statement** (`WITH campaign_guard AS (... FOR SHARE), ...`).
- If the application thread pauses *before* sending the CTE statement, it holds **no database transaction or lock**, and when it wakes up after a rebuild, `campaign_guard` sees `current_epoch != :redisClaimEpoch` and inserts `0` rows.
- If the application thread pauses *after* PostgreSQL executes the CTE statement with autocommit (or single-roundtrip `BEGIN; WITH ...; COMMIT;`), the transaction has **already committed or rolled back** on the database server.

#### 3. Server-Enforced Session Timeouts + Active Zombie Backend Termination (`pg_terminate_backend`)
To defend against any connection that opens an explicit transaction and stalls mid-flight due to a broken TCP socket or kernel hang:
1. Every `promotion_db` pool connection configures PostgreSQL server-side timeouts on startup/checkout:
   - `statement_timeout = '3000ms'` (`3s`)
   - `idle_in_transaction_session_timeout = '3000ms'` (`3s` — enforced by the PostgreSQL backend process timer even if the client process is completely frozen)
   - `lock_timeout = '2000ms'` (`2s`)
2. When the Rebuilder runs `TX_REBUILDER_FENCE_AND_SNAPSHOT`, before acquiring `FOR UPDATE NOWAIT` (or if `lock_timeout = '2000ms'` trips), the Rebuilder executes an administrative cleanup query that terminates any stalled backend holding a lock on that `campaign_id` for longer than `3 seconds` via `pg_terminate_backend(pid)`.

#### 4. Database Engine Defense-in-Depth Trigger (`trg_enforce_campaign_epoch_and_lock`)
Even if a future developer wrote an ad-hoc query against `flash_sale_claims` without the `campaign_guard` CTE, a PostgreSQL `BEFORE INSERT OR UPDATE` trigger on `flash_sale_claims` acquires `FOR KEY SHARE` on `flash_sale_campaigns` and raises an exception if `status != 'ACTIVE'` or `NEW.campaign_epoch != current_epoch` on insert.

---

### 2.3 Exact SQL Schema, Triggers & Single-Statement CTE Pseudocode (`CH-01`)

#### 2.3.1 Updated Schema & Engine-Level Fencing Trigger (`promotion_db`)
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

-- Engine-level defense-in-depth trigger: no row can be inserted/mutated in flash_sale_claims
-- unless flash_sale_campaigns is locked FORSHARE and is ACTIVE in the matching epoch.
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

#### 2.3.2 Exact Single-Statement CTE for `TX_WRITER` (Original or Retrying Writer)
Executed in a **single database round-trip** with `statement_timeout = '3s'`, `idle_in_transaction_session_timeout = '3s'`, `lock_timeout = '2s'`:
```sql
WITH
-- 1. Lock campaign FOR SHARE and verify it is ACTIVE at the exact epoch returned by Redis Lua
campaign_guard AS (
    SELECT campaign_id, current_epoch
    FROM flash_sale_campaigns
    WHERE campaign_id = :campaignId
      AND current_epoch = :redisClaimEpoch
      AND status = 'ACTIVE'
    FOR SHARE
),
-- 2. Insert CLAIMED_RESERVED only if campaign_guard matched 1 row and claim_id is not yet present
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
-- 3. Increment flash_sale_items.claimed_count ONLY if inserted_claim succeeded (first-time insert)
updated_item AS (
    UPDATE flash_sale_items fsi
    SET claimed_count = fsi.claimed_count + ic.quantity
    FROM inserted_claim ic
    WHERE fsi.campaign_id = ic.campaign_id
      AND fsi.sku_id = ic.sku_id
      AND fsi.claimed_count + ic.quantity <= fsi.allocated_quota
    RETURNING fsi.sku_id
),
-- 4. Emit Outbox Event ONLY if updated_item succeeded
inserted_outbox AS (
    INSERT INTO outbox_messages (
        event_id, aggregate_type, aggregate_id, aggregate_version,
        event_type, topic, partition_key, shard_id, payload, headers
    )
    SELECT
        :eventId, 'FlashSaleClaim', ic.claim_id::text, 1,
        'commerce.flashsale.slot_claimed.v1', 'commerce.flashsale.events.v1',
        :customerId::text, mod(abs(hashtext(:customerId::text)), 16), :payloadJsonb, :headersJsonb
    FROM inserted_claim ic
    JOIN updated_item ui ON ui.sku_id = ic.sku_id
    RETURNING event_id
),
-- 5. Complete Idempotency Record ONLY if inserted_outbox succeeded
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
- **Deterministic Application Outcome Handling on the Returned Row**:
  1. If `inserted_status == 'CLAIMED_RESERVED'` and `quota_updated == 1`: `COMMIT` -> return `202 Accepted`.
  2. If `inserted_status IS NULL` and `existing_status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED')`: `COMMIT` -> a prior attempt already persisted the claim; return `202 Accepted`.
  3. If `inserted_status IS NULL` and `existing_status == 'ABANDONED_FENCED'`: `ROLLBACK` -> Reconciler beat the Writer; return `409 Conflict (CLAIM_LEASE_EXPIRED_FENCED)`.
  4. If `epoch_valid == 0` (campaign entered `REBUILDING_GATE` or bumped `current_epoch`): `ROLLBACK` -> return `503 Service Unavailable (Retry-After: 2)`.
  5. If `inserted_status == 'CLAIMED_RESERVED'` and `quota_updated == 0`: `ROLLBACK` -> quota exhausted anomaly; return `409 Conflict`.

#### 2.3.3 Exact Single-Statement CTE for `TX_RECONCILER` (Unacknowledged Redis Intent Lease Expiry)
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
- **Crucial Cross-Epoch Invariant (`F-12`)**:
  - Notice `campaign_guard` requires `current_epoch = :redisClaimEpoch AND status = 'ACTIVE'`.
  - If `current_epoch` has already advanced (`current_epoch > :redisClaimEpoch`), `epoch_valid == 0` and the Reconciler does **nothing**—because the Rebuilder for `current_epoch` already reconstructed Redis strictly from committed PostgreSQL rows (`CLAIMED_RESERVED`, `ORDER_MATERIALIZED`, `PAYMENT_CONFIRMED`), which automatically restored any uncommitted intent lease from the old epoch!

#### 2.3.4 Exact Single-Statement CTE for `TX_EXPIRE_OR_CANCEL` (Committed Claim Expiry / Cancellation)
```sql
WITH campaign_guard AS (
    SELECT campaign_id, current_epoch
    FROM flash_sale_campaigns
    WHERE campaign_id = :campaignId
      AND status = 'ACTIVE'
    FOR SHARE
),
expired_claim AS (
    UPDATE flash_sale_claims fsc
    SET status = :targetTerminalStatus, -- 'EXPIRED' or 'CANCELLED'
        release_epoch = cg.current_epoch,
        stock_returned_to_redis = FALSE,
        version = fsc.version + 1,
        updated_at = NOW()
    FROM campaign_guard cg
    WHERE fsc.claim_id = :claimId
      AND fsc.campaign_id = cg.campaign_id
      AND fsc.status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED')
    RETURNING fsc.claim_id, fsc.campaign_id, fsc.sku_id, fsc.quantity, fsc.release_epoch
),
decremented_item AS (
    UPDATE flash_sale_items fsi
    SET claimed_count = GREATEST(0, fsi.claimed_count - ec.quantity)
    FROM expired_claim ec
    WHERE fsi.campaign_id = ec.campaign_id
      AND fsi.sku_id = ec.sku_id
    RETURNING fsi.sku_id
)
SELECT claim_id, quantity, release_epoch FROM expired_claim;
```

#### 2.3.5 Epoch-Checked `flash_sale_release.lua` & Restock Worker Sequence
When returning stock to Redis for a claim where `stock_returned_to_redis == FALSE`:
1. **Redis Lua Script (`flash_sale_release.lua`)**:
   - `KEYS[1]` = `fs:{campaign_id}:meta` (Hash containing `epoch` and `status`)
   - `KEYS[2]` = `fs:{campaign_id}:sku:{sku_id}:stock`
   - `KEYS[3]` = `fs:{campaign_id}:sku:{sku_id}:buyers`
   - `KEYS[4]` = `fs:{campaign_id}:released_claims`
   - `ARGV[1]` = `claim_id`, `ARGV[2]` = `quantity`, `ARGV[3]` = `release_epoch`, `ARGV[4]` = `customer_id`, `ARGV[5]` = `allocated_quota`
   ```lua
   local status = redis.call('HGET', KEYS[1], 'status')
   local redis_epoch = tonumber(redis.call('HGET', KEYS[1], 'epoch') or '0')
   local release_epoch = tonumber(ARGV[3])
   if status ~= 'ACTIVE' then
       return -1 -- Campaign not active
   end
   if redis_epoch ~= release_epoch then
       return -2 -- Stale epoch! Stock was already restored during epoch rebuild
   end
   if redis.call('HSETNX', KEYS[4], ARGV[1], ARGV[3]) == 0 then
       return 0  -- Already released in this epoch (idempotent no-op)
   end
   local current_stock = tonumber(redis.call('GET', KEYS[2]) or '0')
   local add_qty = tonumber(ARGV[2])
   local max_quota = tonumber(ARGV[5])
   local new_stock = math.min(max_quota, current_stock + add_qty)
   redis.call('SET', KEYS[2], tostring(new_stock))
   redis.call('HDEL', KEYS[3], ARGV[4])
   return 1
   ```
2. If `flash_sale_release.lua` returns `1`, `0`, or `-2` (stale epoch already rebuilt), the worker marks `UPDATE flash_sale_claims SET stock_returned_to_redis = TRUE WHERE claim_id = :claimId`.

#### 2.3.6 Exact Rebuilder Protocol (`TX_REBUILDER_FENCE_AND_SNAPSHOT` & `TX_REBUILDER_ACTIVATE` — Zero Fixed Sleep)
When `Promotion Service` detects a Redis restart, failover, or missing/mismatched epoch:

- **Step R0 — Terminate Any Stalled Backend Holding Locks on `campaign_id` > 3s**:
  ```sql
  SELECT pg_terminate_backend(l.pid)
  FROM pg_locks l
  JOIN pg_stat_activity a ON a.pid = l.pid
  WHERE l.relation = 'flash_sale_campaigns'::regclass
    AND l.granted = TRUE
    AND a.pid <> pg_backend_pid()
    AND (NOW() - a.xact_start) > INTERVAL '3 seconds';
  ```
- **Step R1 — `TX_REBUILDER_FENCE_AND_SNAPSHOT` (Exclusive `FOR UPDATE` Lock + Epoch Increment + Authoritative Snapshot in ONE Transaction)**:
  ```sql
  BEGIN;
  SET LOCAL lock_timeout = '3000ms';
  SET LOCAL statement_timeout = '5000ms';

  -- 1. Acquire EXCLUSIVE FOR UPDATE lock on flash_sale_campaigns.
  --    PostgreSQL lock manager guarantees this statement CANNOT proceed until
  --    100% of currently open TX_WRITER, TX_RECONCILER, and TX_EXPIRE_OR_CANCEL
  --    transactions holding FOR SHARE on this campaign_id have COMMITted or ROLLBACKed!
  UPDATE flash_sale_campaigns
  SET status = 'REBUILDING_GATE',
      current_epoch = current_epoch + 1,
      updated_at = NOW()
  WHERE campaign_id = :campaignId
    AND status IN ('ACTIVE', 'REBUILDING_GATE')
  RETURNING current_epoch;
  -- Let :newEpoch be the returned current_epoch.

  -- 2. Mark all prior EXPIRED / CANCELLED / ABANDONED_FENCED claims (from epochs < :newEpoch)
  --    as stock_returned_to_redis = TRUE, because our snapshot below computes remaining stock
  --    directly from active claims, automatically accounting for all prior releases!
  UPDATE flash_sale_claims
  SET stock_returned_to_redis = TRUE,
      updated_at = NOW()
  WHERE campaign_id = :campaignId
    AND status IN ('EXPIRED', 'CANCELLED', 'ABANDONED_FENCED')
    AND stock_returned_to_redis = FALSE;

  -- 3. Reconcile flash_sale_items.claimed_count to match the exact sum of active claims
  UPDATE flash_sale_items fsi
  SET claimed_count = COALESCE((
      SELECT SUM(fsc.quantity)
      FROM flash_sale_claims fsc
      WHERE fsc.campaign_id = fsi.campaign_id
        AND fsc.sku_id = fsi.sku_id
        AND fsc.status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED')
  ), 0)
  WHERE fsi.campaign_id = :campaignId
  RETURNING sku_id, allocated_quota, claimed_count, (allocated_quota - claimed_count) AS remaining_stock;

  -- 4. Read exact active buyer quantities for Redis reconstruction
  SELECT sku_id, customer_id, SUM(quantity) AS active_qty
  FROM flash_sale_claims
  WHERE campaign_id = :campaignId
    AND status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED')
  GROUP BY sku_id, customer_id;

  COMMIT;
  ```
- **Step R2 — Reconstruct Redis State for `:newEpoch` (While `status == 'REBUILDING_GATE'` Blocks All DB Mutations)**:
  - Write `fs:{campaign_id}:meta` (`status = 'REBUILDING_GATE'`, `epoch = :newEpoch`), `fs:{campaign_id}:sku:{sku_id}:stock = remaining_stock`, and `fs:{campaign_id}:sku:{sku_id}:buyers` into Redis via `MULTI/EXEC`.
- **Step R3 — `TX_REBUILDER_ACTIVATE` (Flip Redis & PostgreSQL Back to `ACTIVE`)**:
  - Set `HSET fs:{campaign_id}:meta status ACTIVE` in Redis, then commit in PostgreSQL:
    ```sql
    UPDATE flash_sale_campaigns
    SET status = 'ACTIVE', updated_at = NOW()
    WHERE campaign_id = :campaignId AND current_epoch = :newEpoch;
    ```

---

### 2.4 Formal Proof & Concurrency Timeline (`Writer` vs. `Reconciler` vs. `Rebuilder`)

#### Theorem (`CH-01` Epoch Fencing Invariant)
*No `TX_WRITER`, `TX_RECONCILER`, or `TX_EXPIRE_OR_CANCEL` carrying `epoch < newEpoch` can commit after `TX_REBUILDER_FENCE_AND_SNAPSHOT` acquires `FOR UPDATE` on `flash_sale_campaigns`, and no mutation can occur while `status = 'REBUILDING_GATE'`.*

#### Proof by Exhaustive Case Analysis
Let $T_{\text{lock}}$ be the instant PostgreSQL grants the exclusive row lock on `flash_sale_campaigns(campaign_id)` to `TX_REBUILDER_FENCE_AND_SNAPSHOT`. Consider any competing transaction $TX_W$ (`epoch = E`):
1. **Case 1 ($TX_W$ acquired `FOR SHARE` on `flash_sale_campaigns` *before* $T_{\text{lock}}$)**:
   - Because PostgreSQL `FOR UPDATE` conflicts with `FOR SHARE`, PostgreSQL's lock manager **blocks `TX_REBUILDER_FENCE_AND_SNAPSHOT` from reaching $T_{\text{lock}}$** until $TX_W$ releases its `FOR SHARE` lock.
   - In PostgreSQL, row-level locks are held until transaction end (`COMMIT` or `ROLLBACK`).
   - If $TX_W$ is healthy, its single-statement CTE completes in `< 5ms` and commits **before** $T_{\text{lock}}$, so its mutation is **100% visible to and included in** `TX_REBUILDER_FENCE_AND_SNAPSHOT`'s snapshot!
   - If $TX_W$ stalls (e.g., broken client connection), PostgreSQL's `idle_in_transaction_session_timeout = 3s` / `statement_timeout = 3s` or `Step R0` (`pg_terminate_backend`) aborts and rolls back $TX_W$ **before** $T_{\text{lock}}$.
   - Therefore, **zero transactions from Case 1 can remain open at or after $T_{\text{lock}}$**.
2. **Case 2 ($TX_W$ requests `FOR SHARE` on `flash_sale_campaigns` *after* $T_{\text{lock}}$)**:
   - While `TX_REBUILDER_FENCE_AND_SNAPSHOT` holds `FOR UPDATE`, $TX_W$ blocks on the row lock.
   - When `TX_REBUILDER_FENCE_AND_SNAPSHOT` commits (`current_epoch = E + 1`, `status = 'REBUILDING_GATE'`), PostgreSQL `READ COMMITTED` (`EvalPlanQual`) re-evaluates $TX_W$'s `campaign_guard` predicate (`WHERE campaign_id = :id AND current_epoch = E AND status = 'ACTIVE'`) against the newly committed tuple (`current_epoch = E + 1, status = 'REBUILDING_GATE'`).
   - The predicate evaluates to `FALSE` (`0` rows returned), `inserted_claim` inserts `0` rows, and $TX_W$ rolls back!

#### Concurrency Timeline Diagram (`M0.2.3`)
```text
Time      Writer W1 (epoch=1, stalled)    Writer W2 (epoch=1, late)       Rebuilder R1 (epoch 1 -> 2)
------------------------------------------------------------------------------------------------------------------------
T=0.00s   Sends single-CTE TX_WRITER;     Paused in JVM GC *before*       -
          acquires FOR SHARE on campaign  sending SQL to PostgreSQL
T=0.10s   (Suppose W1 socket hangs mid-   (Still paused in JVM GC)        Redis restarts! R1 starts rebuild recovery.
          transaction inside Postgres)
T=3.10s   Postgres timer (3s timeout)     (Still paused in JVM GC)        R1 runs Step R0 (pg_terminate_backend for any
          OR Step R0 terminates W1!                                       tx > 3s) and begins TX_REBUILDER_FENCE_AND_SNAPSHOT.
          W1 ROLLS BACK & releases lock.
T=3.11s   -                               (Still paused in JVM GC)        R1 acquires FOR UPDATE on flash_sale_campaigns!
                                                                          Sets current_epoch=2, status='REBUILDING_GATE',
                                                                          reads exact snapshot, and COMMITS.
T=3.15s   -                               (Still paused in JVM GC)        R1 populates Redis (epoch=2) and sets status='ACTIVE'.
T=8.00s   -                               W2 wakes up from 8s GC pause!   -
                                          Sends CTE with epoch=1.
                                          campaign_guard checks:
                                          current_epoch(2) == 1 -> FALSE!
                                          0 rows inserted -> W2 ABORTS!
```

---

## 3. `CH-04` Redesign — Shard-Scoped Single-Writer Lease, Broker `ProducerEpoch` Fencing & Head-Event Cycle

### 3.1 Why the `M0.2.2` 3-Phase Lease-Claimed Outbox Relay Failed (`F-13` & `F-14` Proof)

Let's trace the two distinct concurrency failure modes in `M0.2.2`:

#### Failure Mode 1 (`F-13` — Stale Publisher Across Lease Expiry Produces `[v1, v2, v1]`)
1. **$T = 0\text{s}$**: Relay A claims `O1:v1` in PostgreSQL (`relay_lease_until = T + 30s`).
2. **$T = 1\text{s}$**: Relay A serializes the Kafka `ProduceRequest` for `O1:v1`, and its OS thread/JVM/CLR pauses for `35 seconds` right before flushing the socket.
3. **$T = 31\text{s}$**: `relay_lease_until` expires in PostgreSQL. Relay B claims `O1:v1` (and newly committed `O1:v2`), publishes `O1:v1` followed by `O1:v2` to Kafka partition $P$, and marks both `processed_at = NOW()` in PostgreSQL.
   - Kafka partition $P$ now contains: `[O1:v1 (from B), O1:v2 (from B)]`.
4. **$T = 36\text{s}$**: Relay A resumes from its pause and flushes its TCP socket to the Kafka broker!
   - Why doesn't the PostgreSQL lease stop this? Because the PostgreSQL lease is only checked in Phase 1 and Phase 3; Phase 2 talks directly to the Kafka broker!
   - Why doesn't standard `enable.idempotence = true` stop this? Because Kafka's idempotent producer deduplicates by `(ProducerId, SequenceNumber)`, and independent instances Relay A and Relay B have **different `ProducerId`s**!
   - Consequently, the Kafka broker accepts Relay A's delayed packet and appends `O1:v1` **after** `O1:v2`:
     $$\text{Kafka Partition } P: \quad [\texttt{O1:v1 (B)},\ \texttt{O1:v2 (B)},\ \texttt{O1:v1 (stale from A)}]$$

#### Failure Mode 2 (`F-14` — Multi-Version Batch Crash After Kafka Ack Before DB Update Produces `[v1, v2, v1, v2]`)
Suppose Relay A is the sole writer, claims **both** `O1:v1` and `O1:v2` in Phase 1, publishes `[O1:v1, O1:v2]` to Kafka in Phase 2, receives the broker acknowledgement, and **crashes at $T = 2\text{s}$ right before Phase 3 updates PostgreSQL**!
1. At $T = 2\text{s}$, the Kafka partition already contains committed `[O1:v1, O1:v2]`.
2. In PostgreSQL, both `O1:v1` and `O1:v2` still have `processed_at IS NULL`.
3. At $T = 31\text{s}$, Relay B recovers the expired lease, sees `O1:v1` and `O1:v2` with `processed_at IS NULL`, and re-publishes `[O1:v1, O1:v2]` to Kafka!
4. The Kafka partition now contains:
   $$\text{Kafka Partition } P: \quad [\texttt{O1:v1 (A)},\ \texttt{O1:v2 (A)},\ \texttt{O1:v1 (B)},\ \texttt{O1:v2 (B)}]$$
   Even without a concurrent zombie worker, batching multiple versions of the **same** aggregate before committing `processed_at` in PostgreSQL causes `v1` to be re-published **after** `v2` on crash recovery!

---

### 3.2 The `M0.2.3` Solution: Shard-Scoped Single-Writer + Kafka `transactional.id` Broker Fencing + Head-of-Aggregate Single-Version Cycle

To prevent stale publication at the **actual Kafka broker boundary** AND prevent `[v1, v2, v1, v2]` on crash between Phase 2 and Phase 3, we combine three mechanisms:

#### Mechanism 1 — Deterministic Outbox Shards (`shard_id`) & Monotonic `fencing_epoch`
- Every row inserted into `outbox_messages` computes `shard_id = mod(abs(hashtext(partition_key)), 16)` (16 logical shards per service, `0..15`).
- A control table `outbox_relay_shards (shard_id INT PRIMARY KEY, owner_pod VARCHAR, fencing_epoch BIGINT, lease_until TIMESTAMPTZ)` tracks the single active Relay worker per `shard_id`.

#### Mechanism 2 — Kafka Broker-Enforced Fencing via Deterministic `transactional.id` (`ProducerEpoch`)
- How do we make the **Kafka broker itself** reject TCP packets from a paused Relay A after Relay B takes over `shard_id`?
- We bind each `shard_id` (`0..15`) to a deterministic Kafka **`transactional.id`**:
  $$\texttt{transactional.id} = \texttt{"<service-name>-outbox-shard-"} \mathbin{\Vert} \texttt{shard\_id}$$
- **Mandatory Lease-Acquisition Protocol**:
  1. Whenever a Relay worker acquires a new or expired shard lease in PostgreSQL (`UPDATE outbox_relay_shards SET owner_pod = :podId, fencing_epoch = fencing_epoch + 1, lease_until = NOW() + INTERVAL '30 seconds'`), it **MUST** invoke `kafkaProducer.initTransactions()` for `transactional.id = "<service-name>-outbox-shard-" + shard_id` **before querying or publishing any `outbox_messages` rows**.
  2. When Relay B calls `initTransactions()` with the same `transactional.id`, the **Kafka Transaction Coordinator on the broker synchronously increments the internal `ProducerEpoch`**, aborts any uncommitted transaction from Relay A (`ProducerEpoch - 1`), and fences `ProducerEpoch - 1` across all partition leaders!
  3. If paused Relay A wakes up during Phase 2 and flushes a `ProduceRequest` or `EndTxnRequest` (`commitTransaction()`) to the Kafka broker, **the Kafka broker rejects Relay A's packet at the network boundary with `ProducerFencedException` (`INVALID_PRODUCER_EPOCH`)**!
  4. All Kafka consumers configure `isolation.level = read_committed`, ensuring aborted transactions from fenced producers are never delivered to application code.

#### Mechanism 3 — Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)
- Why did Failure Mode 2 (`[v1, v2, v1, v2]`) happen? Because `v2` of aggregate `O1` was sent to Kafka before `v1` of `O1` was marked `processed_at = NOW()` in PostgreSQL!
- **Rule (`INV-OUTBOX-HEAD-ONLY`)**: In each Phase 1 cycle for `shard_id`, the Relay claims **at most ONE event per `aggregate_id`—specifically, the lowest unpublished `aggregate_version`** (`SELECT DISTINCT ON (aggregate_id) ... ORDER BY aggregate_id, aggregate_version ASC, outbox_sequence ASC LIMIT 100`).
  - Note: Across *different* aggregates (`O1, O2, ..., O100`), up to `100` events are still batched into a single Kafka transaction and a single DB update!
  - However, for any *single* aggregate `O1`, version `v2` is **never claimed or sent to Kafka** until version `v1` has been committed in Kafka (`commitTransaction()`) **AND** marked `processed_at = NOW()` in PostgreSQL!
- **What happens if Relay A commits `O1:v1` in Kafka (`commitTransaction()`) and crashes right before Phase 3 marks `O1:v1` as `processed_at = NOW()` in PostgreSQL?**
  1. Because of `INV-OUTBOX-HEAD-ONLY`, `O1:v2` was **never sent to Kafka** by Relay A!
  2. When Relay B takes over `shard_id` and calls `initTransactions()`, it queries PostgreSQL and sees `O1:v1` is still the lowest unpublished version (`processed_at IS NULL`).
  3. Relay B claims and publishes `O1:v1` in Cycle 1, marks `O1:v1` `processed_at = NOW()` in Phase 3, and only in Cycle 2 claims and publishes `O1:v2`!
  4. Therefore, the `READ_COMMITTED` Kafka partition log contains:
     $$[\texttt{O1:v1 (from A)},\ \texttt{O1:v1 (duplicate from B)},\ \texttt{O1:v2 (from B)}]$$
     The version sequence in Kafka is **`[1, 1, 2]` — strictly monotonically non-decreasing (`v1` NEVER appears after `v2`)**!

---

### 3.3 Exact SQL Schema & 3-Phase Shard-Fenced Relay Protocol (`CH-04`)

#### 3.3.1 Updated `outbox_relay_shards` & `outbox_messages` Schema
```sql
CREATE TABLE outbox_relay_shards (
    shard_id            INTEGER PRIMARY KEY CHECK (shard_id BETWEEN 0 AND 15),
    owner_pod           VARCHAR(128) NULL,
    fencing_epoch       BIGINT       NOT NULL DEFAULT 0,
    broker_fenced_epoch BIGINT       NOT NULL DEFAULT 0,
    lease_until         TIMESTAMPTZ  NOT NULL DEFAULT '-infinity',
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Seed 16 shards (0..15) on service migration startup
INSERT INTO outbox_relay_shards (shard_id)
SELECT generate_series(0, 15)
ON CONFLICT (shard_id) DO NOTHING;

CREATE TABLE outbox_messages (
    outbox_sequence     BIGSERIAL UNIQUE NOT NULL,
    event_id            UUID PRIMARY KEY,
    shard_id            INTEGER      NOT NULL CHECK (shard_id BETWEEN 0 AND 15),
    aggregate_type      VARCHAR(64)  NOT NULL,
    aggregate_id        VARCHAR(128) NOT NULL,
    aggregate_version   BIGINT       NOT NULL CHECK (aggregate_version >= 1),
    event_type          VARCHAR(128) NOT NULL,
    topic               VARCHAR(128) NOT NULL,
    partition_key       VARCHAR(128) NOT NULL,
    payload             JSONB        NOT NULL,
    headers             JSONB        NOT NULL,
    claimed_fencing_epoch BIGINT     NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    processed_at        TIMESTAMPTZ  NULL,
    retry_count         INTEGER      NOT NULL DEFAULT 0,
    last_error          TEXT         NULL,
    CONSTRAINT uq_outbox_aggregate_version UNIQUE (aggregate_type, aggregate_id, aggregate_version, event_type)
);

CREATE INDEX idx_outbox_shard_head
    ON outbox_messages (shard_id, aggregate_id, aggregate_version ASC, outbox_sequence ASC)
    WHERE processed_at IS NULL;
```

#### 3.3.2 Exact Relay Execution Pseudocode & SQL
```text
FUNCTION poll_and_publish_shard(shardId, podId):
    -- STEP 0: Acquire or Renew Shard Lease in PostgreSQL (< 1ms TX)
    row = DB.querySingle("""
        UPDATE outbox_relay_shards
        SET owner_pod = :podId,
            fencing_epoch = CASE
                WHEN owner_pod = :podId AND lease_until > NOW() THEN fencing_epoch
                ELSE fencing_epoch + 1
            END,
            lease_until = NOW() + INTERVAL '30 seconds',
            updated_at = NOW()
        WHERE shard_id = :shardId
          AND (owner_pod = :podId OR lease_until <= NOW())
        RETURNING fencing_epoch, broker_fenced_epoch;
    """)
    IF row IS NULL:
        RETURN -- Another active pod owns this shard

    -- STEP 0.5: If fencing_epoch > broker_fenced_epoch, fence any prior producer at Kafka Broker FIRST!
    IF row.fencing_epoch > row.broker_fenced_epoch:
        txProducer = getOrCreateTransactionalProducer(transactionalId = serviceName + "-outbox-shard-" + shardId)
        -- Kafka Broker increments ProducerEpoch and aborts/fences any prior zombie producer for this shard!
        txProducer.initTransactions(timeout = 5s)
        DB.execute("""
            UPDATE outbox_relay_shards
            SET broker_fenced_epoch = :fencingEpoch
            WHERE shard_id = :shardId AND owner_pod = :podId AND fencing_epoch = :fencingEpoch;
        """)

    -- PHASE 1: Claim ONLY the single lowest unpublished version (head event) per aggregate_id in this shard (< 2ms TX)
    headEvents = DB.query("""
        WITH shard_guard AS (
            SELECT shard_id, fencing_epoch
            FROM outbox_relay_shards
            WHERE shard_id = :shardId
              AND owner_pod = :podId
              AND fencing_epoch = :fencingEpoch
              AND broker_fenced_epoch = :fencingEpoch
              AND lease_until > NOW() + INTERVAL '5 seconds'
            FOR SHARE
        ),
        head_per_aggregate AS (
            SELECT DISTINCT ON (m.aggregate_id)
                   m.event_id, m.aggregate_id, m.aggregate_version, m.outbox_sequence
            FROM outbox_messages m
            JOIN shard_guard sg ON sg.shard_id = m.shard_id
            WHERE m.processed_at IS NULL
            ORDER BY m.aggregate_id, m.aggregate_version ASC, m.outbox_sequence ASC
            LIMIT 100
        )
        UPDATE outbox_messages m
        SET claimed_fencing_epoch = :fencingEpoch
        FROM head_per_aggregate h
        WHERE m.event_id = h.event_id
        RETURNING m.event_id, m.aggregate_type, m.aggregate_id, m.aggregate_version,
                  m.event_type, m.topic, m.partition_key, m.payload, m.headers, m.claimed_fencing_epoch;
    """)
    IF headEvents IS EMPTY:
        RETURN

    -- PHASE 2: Publish batch inside Kafka Transaction (fenced at Broker by ProducerEpoch!)
    TRY:
        txProducer.beginTransaction()
        FOR evt IN headEvents:
            record = KafkaRecord(
                topic = evt.topic,
                key = evt.partition_key, -- Deterministic murmur2 hash -> same Kafka partition
                value = evt.payload,
                headers = evt.headers + { "x-fencing-epoch": evt.claimed_fencing_epoch,
                                          "x-aggregate-version": evt.aggregate_version }
            )
            txProducer.send(record)
        txProducer.commitTransaction(timeout = 5s)
    CATCH ProducerFencedException:
        -- Another pod stole the shard lease and called initTransactions()!
        -- Broker rejected our commitTransaction(); zero records from this batch are visible to READ_COMMITTED consumers.
        closeProducer(shardId)
        RETURN
    CATCH KafkaException:
        txProducer.abortTransaction()
        RETURN

    -- PHASE 3: Mark head events as processed_at = NOW() (< 2ms TX)
    -- Only AFTER Phase 3 commits can the next cycle claim aggregate_version + 1 for these aggregates!
    DB.execute("""
        UPDATE outbox_messages m
        SET processed_at = NOW()
        FROM outbox_relay_shards s
        WHERE m.event_id = ANY(:eventIds)
          AND m.shard_id = s.shard_id
          AND s.shard_id = :shardId
          AND s.owner_pod = :podId
          AND s.fencing_epoch = :fencingEpoch;
    """)
```

---

### 3.4 Concurrency & Crash Timelines for `CH-04`

#### Timeline 1: Paused Relay A (`> 30s`) vs. Recovery Relay B (The User's Exact Scenario)
```text
Time      Relay A (Pod 1, shard_id=3)               Kafka Broker (TxnCoord + Partition)       Relay B (Pod 2, shard_id=3)
------------------------------------------------------------------------------------------------------------------------------------
T=0.0s    Claims shard_id=3 (fencing_epoch=1).      initTransactions("...-shard-3") ->        -
          Claims head event O1:v1.                  Assigns ProducerId=900, ProducerEpoch=0.
T=0.5s    Calls beginTransaction(), sends O1:v1,    Buffers uncommitted O1:v1 (Epoch=0).      -
          then PAUSES 35s in JVM/CLR GC before      (Not visible to READ_COMMITTED consumers)
          commitTransaction()!
T=30.5s   (Still paused in GC)                      -                                         Sees shard_id=3 lease expired!
                                                                                              Bumps fencing_epoch=2 in Postgres.
T=30.6s   (Still paused in GC)                      Receives initTransactions("...-shard-3")  Calls initTransactions("...-shard-3")
                                                    from Relay B!                             BEFORE reading any DB rows!
                                                    1. Bumps ProducerEpoch: 0 -> 1!
                                                    2. ABORTS uncommitted O1:v1 from Epoch=0!
                                                    3. Fences ProducerEpoch=0 on broker!
T=30.8s   (Still paused in GC)                      Appends & commits O1:v1 (Epoch=1).        Cycle 1: Claims O1:v1, commits to
                                                                                              Kafka, marks O1:v1 processed_at=NOW().
T=31.0s   (Still paused in GC)                      Appends & commits O1:v2 (Epoch=1).        Cycle 2: Claims O1:v2 (now head!),
                                                    Log: [O1:v1(B), O1:v2(B)].                commits to Kafka, marks processed_at.
T=35.5s   Wakes up from 35s pause! Flushes          Broker checks ProducerEpoch:              -
          O1:v1 / commitTransaction(Epoch=0)        req.Epoch(0) < currentEpoch(1)!
          over TCP socket to Kafka broker!          REJECTS with ProducerFencedException!
                                                    Stale v1 is NEVER appended after v2!
```

#### Timeline 2: Relay A Crashes *After* Kafka `commitTransaction()` *Before* Phase 3 DB Update
```text
Time      Relay A (Pod 1, shard_id=3)               Kafka Broker (READ_COMMITTED Log)         Relay B (Pod 2, shard_id=3)
------------------------------------------------------------------------------------------------------------------------------------
T=0.0s    O1 has BOTH v1 and v2 in Postgres.        Log: []                                   -
          Because of DISTINCT ON (aggregate_id),
          Phase 1 claims ONLY O1:v1 (NOT v2!).
T=0.2s    Commits O1:v1 to Kafka!                   Log: [O1:v1 (Epoch=0)]                    -
          CRASHES (OOM / SIGKILL) before Phase 3!
          (Note: O1:v2 was NEVER sent to Kafka!)
T=30.5s   (Dead)                                    initTransactions("...-shard-3") ->        Claims shard_id=3 (fencing_epoch=2).
                                                    Bumps ProducerEpoch: 0 -> 1.              Queries head event for O1: sees O1:v1
                                                                                              still has processed_at IS NULL!
T=30.7s   (Dead)                                    Log: [O1:v1 (Epoch=0), O1:v1 (Epoch=1)]   Cycle 1: Publishes O1:v1 & marks
                                                                                              O1:v1.processed_at = NOW() in DB.
T=30.9s   (Dead)                                    Log: [O1:v1, O1:v1, O1:v2 (Epoch=1)]      Cycle 2: Claims O1:v2, publishes O1:v2,
                                                    (Versions: 1 -> 1 -> 2, MONOTONIC!)       & marks O1:v2.processed_at = NOW().
```

---

### 3.5 Explicit Delivery Contract & Consumer Implications (`CH-04`)

We explicitly define both the **Primary Broker-Fenced Contract** and the **Fallback Defense-in-Depth Consumer Contract**:

| Contract Layer | Guarantees Provided | Residual Anomalies Possible | Mandatory Consumer Invariant |
| :--- | :--- | :--- | :--- |
| **Layer 1: Shard-Leased + Kafka `transactional.id` (`ProducerEpoch`) + Head-Event-Only Relay (`isolation.level = read_committed`)** | 1. Stale paused producers (`ProducerEpoch < current`) are rejected at the Kafka broker (`ProducerFencedException`).<br>2. Because `v+1` is never sent until `v` is marked `processed_at = NOW()` in PostgreSQL, a crash between Kafka commit and DB completion can only repeat the head version (`[v1, v1, v2]`), **never** invert order (`[v1, v2, v1]`). | **At-Least-Once Duplicate Delivery of Head Event (`[v1, v1, v2]`)** when a Relay crashes in the `<2ms` window after `commitTransaction()` and before Phase 3 DB update. | Consumer MUST deduplicate `event_id` via `inbox_messages (event_id, consumer_group)` AND treat `incoming.aggregate_version <= aggregate.last_applied_version` as an idempotent `NOOP`. |
| **Layer 2: Defense-in-Depth Consumer Contract (If Non-Transactional Producer or Manual DLQ Replay Occurs)** | Even if an operator manually replays an old event from a DLQ topic or a non-transactional producer is used in a degraded test mode (producing `[v1, v2, v1]` or `[v1, v3]`), the consumer database state machine remains 100% consistent. | Out-of-order replay (`v1` after `v2`) or sequence gap (`v3` before `v2`) from manual DLQ tooling or broker partition reassignment anomalies. | 1. `incoming.version <= last_applied_version` -> **Idempotent No-Op** (never regress state).<br>2. `incoming.version == last_applied_version + 1` -> **Apply transition** & set `last_applied_version = incoming.version`.<br>3. `incoming.version > last_applied_version + 1` -> **Sequence Gap**: if Terminal Tombstone (`OrderCancelled`/`OrderExpired`), apply tombstone; otherwise route to `.retry` topic until missing version arrives. |

---

## 4. Explicit Assumptions, Limitations & Human Decisions (`HUMAN_DECISION`)

### 4.1 Explicit Architectural Assumptions & Limitations
1. **`CH-01` Lock Contention Assumption**:
   - In PostgreSQL 17, `SELECT ... FOR SHARE` on `flash_sale_campaigns` is a shared lock that does **not** block concurrent `TX_WRITER` transactions from executing in parallel; per-SKU serialization occurs on `UPDATE flash_sale_items` (`FOR NO KEY UPDATE`). However, during a hot flash sale, thousands of `FOR SHARE` lock acquisitions on a single `flash_sale_campaigns` tuple can create PostgreSQL `MultiXact` metadata traffic if transactions stay open across multiple network round-trips. Executing `TX_WRITER` as a **single-roundtrip Data-Modifying CTE** keeps transaction duration to `< 2ms`, minimizing `MultiXact` duration.
2. **`CH-01` Superuser / Role Privileges for `Step R0` (`pg_terminate_backend`)**:
   - In PostgreSQL, `pg_terminate_backend(pid)` works without superuser privileges as long as the Rebuilder connects with the **same database role (`promotion_app_role`)** as the Writer/Reconciler connections (or a role granted `pg_signal_backend`). This is satisfied by our `ADR-0002` per-service role design.
3. **`CH-04` Single-Aggregate Burst Latency**:
   - Because Phase 1 claims `DISTINCT ON (aggregate_id)` (1 version per aggregate per cycle), if a single aggregate `O1` emits 3 events (`v1, v2, v3`) in the same database transaction, they are published across 3 consecutive Relay cycles (`~5–10ms` per cycle = `~15–30ms` total for `v3`), whereas 100 *distinct* aggregates (`O1..O100`) are published concurrently in a single cycle.

### 4.2 Decisions Requiring Your Explicit Approval (`HUMAN_DECISION`)
1. **`HD-01 (Revised in M0.2.3)` — `CH-01` Lock-Serialized `FOR SHARE`/`FOR UPDATE` Epoch Barrier + Single-CTE Execution (Replacing the `5.5s` Fixed Sleep)**:
   - Approve replacing the `M0.2.2` `5.5s` sleep with the `FOR SHARE` / `FOR UPDATE` lock barrier on `flash_sale_campaigns` + `3s` `idle_in_transaction_session_timeout` + `Step R0` `pg_terminate_backend` + `release_epoch` validation in `flash_sale_release.lua`.
2. **`HD-04 (New in M0.2.3)` — `CH-04` Shard-Scoped Kafka `transactional.id` Broker Fencing + Head-of-Aggregate Single-Version-Per-Cycle (`DISTINCT ON (aggregate_id)`)**:
   - Approve using 16 deterministic Outbox shards (`<service>-outbox-shard-0..15`) with Kafka `initTransactions()` broker-level `ProducerEpoch` fencing (`isolation.level = read_committed`) and claiming at most 1 version per `aggregate_id` per cycle so `v+1` is never sent to Kafka before `v` is marked `processed_at = NOW()` in PostgreSQL.

---

## 5. Additional Reproducible Runtime Test Specifications (`NEEDS_EVIDENCE` — Scheduled for `M1–M7`)

| Test ID | Challenge | Reproducible Runtime Test Specification | Classification |
| :--- | :--- | :--- | :--- |
| **`SPEC-CH01-T3`** | `CH-01` | Open a PostgreSQL session holding `SELECT ... FROM flash_sale_campaigns WHERE campaign_id = :id AND current_epoch = 1 FOR SHARE`, pause the thread for `6s`, and start `TX_REBUILDER_FENCE_AND_SNAPSHOT`. Verify `idle_in_transaction_session_timeout = 3s` / `Step R0` terminates the stalled session, `TX_REBUILDER` bumps `current_epoch = 2`, and any late single-CTE Writer carrying `redisClaimEpoch = 1` matches `0` rows in `campaign_guard` and aborts. | **`NEEDS_EVIDENCE`** *(To execute in `M3`)* |
| **`SPEC-CH01-T4`** | `CH-01` | Expire claim `C1` in `epoch = 1` (`release_epoch = 1, stock_returned_to_redis = FALSE`), run `TX_REBUILDER_FENCE_AND_SNAPSHOT` (`current_epoch = 2`), and then invoke `flash_sale_release.lua` with `ARGV[3] = 1` (`release_epoch = 1`). Verify Redis Lua returns `-2` (`STALE_EPOCH`) and does not increment `epoch = 2` stock above `allocated_quota - claimed_count`. | **`NEEDS_EVIDENCE`** *(To execute in `M3`)* |
| **`SPEC-CH04-T2`** | `CH-04` | In Testcontainers (`Postgres + Kafka KRaft`), have Relay A (`shard_id = 3`) begin a Kafka transaction (`transactional.id = "order-service-outbox-shard-3"`), send `O1:v1`, and pause before `commitTransaction()`. Have Relay B steal `shard_id = 3`, call `initTransactions()`, and publish `O1:v1` (Cycle 1) and `O1:v2` (Cycle 2). Resume Relay A and call `commitTransaction()`. Verify Kafka broker throws `ProducerFencedException` to Relay A and a `READ_COMMITTED` consumer receives strictly `[O1:v1, O1:v2]`. | **`NEEDS_EVIDENCE`** *(To execute in `M1/M3`)* |
| **`SPEC-CH04-T3`** | `CH-04` | Insert `O1:v1` and `O1:v2` into `outbox_messages`. Crash Relay A immediately after `txProducer.commitTransaction()` in Cycle 1 (`O1:v1`) before Phase 3 updates PostgreSQL. Run Relay B for 2 cycles. Verify `O1:v2` was not sent by Relay A, Relay B publishes `[O1:v1]` in Cycle 1 and `[O1:v2]` in Cycle 2 (`[v1, v1, v2]` in Kafka), and the Consumer Inbox applies `v1` once and `v2` once. | **`NEEDS_EVIDENCE`** *(To execute in `M1/M3`)* |
