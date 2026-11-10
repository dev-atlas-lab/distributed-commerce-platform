# ADR-0005: Flash Sale Concurrency Architecture, Reservation Expiration & 3-Tier Locking Strategy

- **Status:** `ACCEPTED` (Approved in M0.1 — Q4 Option A + Idempotency & Reconciliation Safeguards)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our flagship Flash Sale scenario, `100,000` users attempt to buy `1,000` units of a hot SKU within seconds:
1. Direct PostgreSQL `SELECT ... FOR UPDATE` on a single SKU row under 100K concurrent hits saturates connection pools and locks up the database.
2. JPA/EF Optimistic Locking (`@Version`) on a hot SKU causes a `99%` abort-and-retry storm.
3. Naive Redis `GET` + `DECR` in application code creates race conditions and overselling.
4. **Unpaid Reservation Expiration (`Q4`)**: When a Flash Sale winner fails to complete payment within the `10-minute` reservation window, we must decide how expired stock is returned without double-releasing stock (if an expiry job and a user cancellation happen concurrently) or leaking stock between Redis and PostgreSQL.

## 2. Options Considered
- **Option A**: PostgreSQL Pessimistic Row Lock (`SELECT ... FOR UPDATE`) for all traffic.
- **Option B**: Application-level Distributed Lock (`Redlock`) wrapping a PostgreSQL transaction.
- **Option C (Chosen)**: **3-Tier Concurrency Architecture (Redis Atomic Lua Gate for Flash Sale + Single-Statement Conditional Atomic SQL Update for Standard Stock + Optimistic `@Version` for Low-Contention Entities) with Option A Active-Pool Expiration Return & Idempotent Reconciliation Safeguards**.

## 3. Decision (`ACCEPTED`)
1. **Tier 1 — Flash Sale Hot Path (`Promotion Service` + Redis Lua + Kafka Queue-Leveling)**:
   - Pre-warm allocated Flash Sale quota into Redis before campaign launch (`flashsale:{campaignId}:sku:{skuId}:stock`).
   - Execute `flash_sale_claim.lua` (`EVALSHA`) atomically in Redis single-threaded memory to verify campaign window, enforce per-user purchase limits (`HINCRBY` on buyer hash), and decrement stock (`DECRBY`).
   - Immediately reject excess requests at the edge (`409 Conflict` in `<10ms`, `0` DB queries).
   - For winners, persist `FlashSaleClaim` + Outbox `FlashSaleSlotClaimed` and materialize the `Order` and `StockReservation` asynchronously over Kafka.
2. **Tier 2 — Unpaid Reservation Expiration Policy (`Q4 Option A — ACCEPTED`)**:
   - When a `10-minute` Flash Sale reservation expires unpaid (or is cancelled by the buyer before payment):
     - **If the Flash Sale campaign is still `ACTIVE` (`now < ends_at`)**: An idempotent Lua release script (`flash_sale_release.lua`) atomically checks that `claim_id` has not already been released (`HSETNX flashsale:{campaignId}:sku:{skuId}:released_claims {claimId} 1`), decrements the user's buyer count (`HINCRBY buyers {customerId} -qty`), and increments live Redis stock (`INCRBY stock qty` capped at `allocated_quota`).
     - **If the Flash Sale campaign has `ENDED` (`now >= ends_at`)**: The released stock is NOT returned to Redis; instead, `Inventory Service` reconciles the unpurchased `flash_sale_allocated_qty` back into standard warehouse `available_qty`.
   - **Reconciliation Safeguard**: A 30-second background **Flash Sale Reconciliation Worker** compares Redis `allocated_quota - current_redis_stock` against active/committed PostgreSQL `flash_sale_claims` and heals any discrepancy caused by pod crashes or network drops.
3. **Tier 3 — Standard Inventory Reservation (`Inventory Service` PostgreSQL)**:
   - Use single-statement conditional atomic SQL (`UPDATE stock_items SET available_qty = available_qty - :qty, reserved_qty = reserved_qty + :qty, version = version + 1 WHERE sku_id = :skuId AND available_qty >= :qty`) combined with deterministic `ORDER BY sku_id ASC` on multi-line orders to eliminate deadlocks and optimistic retry storms.
4. **Tier 4 — Low-Contention Entities (`Order`, `Product`, `Customer`)**:
   - Standard `@Version` / `xmin` Optimistic Concurrency Control.

## 4. Consequences & Trade-offs
- **Positive**: Protects PostgreSQL from spike collapse; guarantees `0` oversold units; returns unpaid Flash Sale slots to active shoppers fairly without double-restocking via `released_claims` idempotency guard.
- **Negative / Cost**: Requires maintaining both `flash_sale_claim.lua` and `flash_sale_release.lua` plus the 30s reconciliation loop.

## 5. Rejected Alternatives
- **Holding expired stock for manual second-chance waves (`Q4 Option B`)**: Rejected because automatic return to the active campaign pool (`Q4 Option A`) maximizes conversion during the live campaign window while idempotency guards prevent double-return bugs.
