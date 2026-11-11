# ADR-0005: Flash Sale Concurrency Architecture, Atomic DB/Lua Release & Fenced Reconciliation

- **Status:** `ACCEPTED` (`Q4 Option A` Accepted in `M0.1`; `CH-01` Fenced Reconciliation & Redis Failover Design Approved in Principle, Pending Final Validation in `M0.2.1`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our Flash Sale scenario (`100,000` users competing for `1,000` units):
1. Redis Lua (`flash_sale_claim.lua`) acts as the fast admission gate while PostgreSQL (`promotion_db`) is the authoritative system of record.
2. Under `Q4 Option A` (`ACCEPTED`), expired unpaid reservations return stock to the active Redis campaign pool, requiring strict single-transaction DB atomicity, deterministic lock serialization when the original writer and reconciler collide, atomic Lua release deduplication (`flash_sale_release.lua`), and a documented Redis failover recovery procedure.

## 2. Options Considered
- **Option A**: Direct PostgreSQL row locking for all 100K requests.
- **Option B**: Unfenced 30-second timeout rollback.
- **Option C**: **3-Tier Concurrency Architecture + Single-TX Claim Persistence + PostgreSQL PK-Serialized Tombstone Fencing (`ABANDONED_FENCED`) + Atomic `flash_sale_release.lua` + `REBUILDING_GATE` Redis Failover Recovery (`CH-01`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - **Tier 1 (Flash Sale Gate)**: Redis Lua admission gate + asynchronous Kafka order materialization.
   - **Tier 2 (`Q4 Option A` Expiry)**: Expired reservations return stock to the active Redis pool while the campaign is `ACTIVE`, or reconcile to warehouse stock after `ENDED`.
   - **Tier 3 (Standard Stock)**: Conditional atomic SQL (`UPDATE stock_items ... WHERE available_qty >= :qty`) ordered by `sku_id ASC`.
   - **Tier 4 (Low-Contention Entities)**: `@Version` Optimistic Concurrency Control.
2. **Validated `M0.2.1` Refinements (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-01`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Privilege-Encapsulated 8-Path Stored Procedures & Non-Locking Pre-Lock Witness Triggers (`M0_2_5_LOCK_AND_KAFKA_OWNERSHIP_REVIEW.md`)**: Direct `INSERT, UPDATE, DELETE` privileges on `flash_sale_campaigns`, `flash_sale_claims`, and `flash_sale_items` are revoked from `promotion_app_role` (which in PostgreSQL also blocks direct `SELECT ... FOR UPDATE/SHARE`). All 8 mutation paths (`fn_mp01` Writer, `fn_mp02` Reconciler, `fn_mp03` Expire/Cancel, `fn_mp04` Restock Finalize, `fn_mp05` Order/Payment Progress, `fn_mp06` Admin Quota Config, `fn_mp07` Rebuilder Fence & Snapshot, `fn_mp08` Campaign Lifecycle) are encapsulated as imperative `SECURITY DEFINER` PL/pgSQL procedures where `Statement 1` locks `flash_sale_campaigns` and sets a transaction-local witness (`promotion.locked_campaign_<uuid>`) before `Statement 2` (`flash_sale_claims` by `claim_id ASC`) or `Statement 3` (`flash_sale_items` by `sku_id ASC`) executes. Non-locking `BEFORE INSERT OR UPDATE OR DELETE` triggers (`trg_verify_claims_campaign_prelocked`, `trg_verify_items_campaign_prelocked`) verify the witness in memory (`SQLSTATE P0004`) without ever introducing reverse `Table 2/3 -> Table 1` lock wait edges.
   - **Concurrent Writer vs. Reconciler Serialization**: Both Writer and Reconciler use `INSERT INTO flash_sale_claims ... ON CONFLICT (claim_id) DO NOTHING RETURNING status` + fallback `SELECT status`. PostgreSQL's `PRIMARY KEY (claim_id)` index lock serializes concurrent execution: if `ABANDONED_FENCED` committed first, the delayed Writer sees `status == 'ABANDONED_FENCED'`, aborts, and rolls back its transaction.
   - **PostgreSQL-Gated & Epoch-Validated Lua Release (`flash_sale_release.lua`)**: Every terminal release (`ABANDONED_FENCED`, `EXPIRED`, `CANCELLED`) records `release_epoch = current_epoch` and `stock_returned_to_redis = FALSE`. `flash_sale_release.lua` validates `redis_epoch == release_epoch` (`ARGV[3]`) and `HSETNX released_claims` before incrementing stock, and `MP-04` (`TX_RESTOCK_FINALIZE`) verifies `current_epoch == release_epoch` under `FOR SHARE` when setting `stock_returned_to_redis = TRUE`.
   - **Strict Separation of Correctness Guarantee (`FOR UPDATE` Mutual Exclusion) vs. Liveness Policies**: On Redis restart/failover, `TX_REBUILDER_FENCE_AND_SNAPSHOT` (`MP-07`) acquires an exclusive `FOR UPDATE` lock on `flash_sale_campaigns` (`status = 'REBUILDING_GATE', current_epoch = current_epoch + 1`). PostgreSQL's lock manager provides the **sole correctness guarantee** (blocking `FOR UPDATE` until all prior `FOR SHARE` transactions finish, and rejecting all subsequent old-epoch transactions via `EvalPlanQual`), while `idle_in_transaction_session_timeout = 3s`, `statement_timeout = 3s`, and `pg_terminate_backend` serve strictly as **operational liveness bounds**. All 5 Redis campaign keys receive a `24h` TTL (`EXPIRE 86400`) upon `RECONCILED`.

## 4. Consequences & Trade-offs
- **Positive**: Provably zero oversell across pod crashes, network stalls, concurrent expiry/cancellation, and Redis restarts.
- **Negative / Cost**: Brief `503 Retry-After: 5` pause (`<2s`) if the Redis instance restarts mid-campaign while state is rebuilt from PostgreSQL.

## 5. Rejected Alternatives
- **Option B (Unfenced timeout rollback)**: Rejected because network delays can cause late DB commits after an unfenced Redis rollback.
