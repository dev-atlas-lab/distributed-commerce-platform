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
   - **Single-TX DB Atomicity**: `flash_sale_claims` insert, `flash_sale_items.claimed_count` update, `outbox_messages` insert, and `idempotency_records` completion occur in one local PostgreSQL transaction.
   - **Concurrent Writer vs. Reconciler Serialization**: Both Writer and Reconciler use `INSERT INTO flash_sale_claims ... ON CONFLICT (claim_id) DO NOTHING RETURNING status` + fallback `SELECT status`. PostgreSQL's `PRIMARY KEY (claim_id)` index lock serializes concurrent execution: if `ABANDONED_FENCED` committed first, the delayed Writer sees `status == 'ABANDONED_FENCED'`, aborts, and rolls back its transaction.
   - **PostgreSQL-Gated Atomic Lua Release (`flash_sale_release.lua`)**: Before calling `flash_sale_release.lua`, the worker verifies `stock_returned_to_redis == FALSE` in PostgreSQL and updates `stock_returned_to_redis = TRUE` upon release—preventing double-restock even if a duplicate Kafka event arrives after Redis `released_claims` TTL expires.
   - **Epoch-Fenced Redis Failover & Cleanup**: On Redis restart/failover (`appendfsync everysec`), `Promotion Service` increments `flash_sale_campaigns.current_epoch` in PostgreSQL (`REBUILDING_GATE`, fencing off any pre-crash in-flight claims), waits `5.5s` for open DB transactions to drain, reconstructs exact stock and buyer sets from PostgreSQL `flash_sale_claims`, and resumes `ACTIVE`. All 5 Redis campaign keys receive a `24h` TTL (`EXPIRE 86400`) upon `RECONCILED`.

## 4. Consequences & Trade-offs
- **Positive**: Provably zero oversell across pod crashes, network stalls, concurrent expiry/cancellation, and Redis restarts.
- **Negative / Cost**: Brief `503 Retry-After: 5` pause (`<2s`) if the Redis instance restarts mid-campaign while state is rebuilt from PostgreSQL.

## 5. Rejected Alternatives
- **Option B (Unfenced timeout rollback)**: Rejected because network delays can cause late DB commits after an unfenced Redis rollback.
