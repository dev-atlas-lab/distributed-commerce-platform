# ADR-0005: Flash Sale Concurrency Architecture (Redis Lua Atomic Gate + 3-Tier Locking Strategy)

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our flagship Flash Sale scenario, `100,000` users attempt to buy `1,000` units of a hot SKU within seconds.
- If all `100,000` requests hit PostgreSQL directly with `SELECT ... FOR UPDATE`, 99,999 connections queue on the single SKU row lock, exhausting connection pools and crashing the database.
- If we use JPA/EF Optimistic Locking (`@Version`) on a hot SKU, `99%` of concurrent transactions abort with `OptimisticLockingFailureException`, causing an expensive retry storm.
- If we use a naive Redis `GET` followed by `DECR` in application code, race conditions cause massive overselling.

## 2. Options Considered
- **Option A: PostgreSQL Pessimistic Row Lock (`SELECT ... FOR UPDATE`) for all traffic**.
- **Option B: Application-level Distributed Lock (`Redlock`) wrapping a PostgreSQL transaction**.
- **Option C: 3-Tier Concurrency Architecture (Redis Atomic Lua Gate for Flash Sale + Single-Statement Conditional Atomic SQL Update for Standard Stock + Optimistic `@Version` for Low-Contention Entities)**.

## 3. Decision
Adopt **Option C**:
1. **Tier 1 — Flash Sale Hot Path (`Promotion Service` + Redis Lua + Kafka Queue-Leveling)**:
   - Pre-warm allocated Flash Sale quota into Redis before campaign launch.
   - Execute `flash_sale_claim.lua` (`EVALSHA`) atomically in Redis single-threaded memory to verify campaign window, enforce per-user purchase limits (`HINCRBY` on buyer hash), and decrement stock (`DECRBY`).
   - Immediately reject the `99,000` excess requests at the edge (`409 Conflict` in `<10ms`, `0` DB queries).
   - For the `1,000` winners, persist `FlashSaleClaim` + Outbox `FlashSaleSlotClaimed` and materialize the `Order` and `StockReservation` asynchronously over Kafka.
   - Run a 30-second **Reconciliation Worker** comparing Redis claims vs. PostgreSQL claims to recover any orphaned slot if a pod crashes mid-request.
2. **Tier 2 — Standard Inventory Reservation (`Inventory Service` PostgreSQL)**:
   - Use single-statement conditional atomic SQL (`UPDATE stock_items SET available_qty = available_qty - :qty, reserved_qty = reserved_qty + :qty, version = version + 1 WHERE sku_id = :skuId AND available_qty >= :qty`) combined with deterministic `ORDER BY sku_id ASC` on multi-line orders to eliminate deadlocks and optimistic retry storms.
3. **Tier 3 — Low-Contention Entities (`Order`, `Product`, `Customer`)**:
   - Standard `@Version` / `xmin` Optimistic Concurrency Control.

## 4. Consequences & Trade-offs
- **Positive**: Protects PostgreSQL from spike collapse; guarantees `0` oversold units and `0` duplicate user claims; achieves sub-50ms Flash Sale response times.
- **Negative / Cost**: Requires pre-warming stock into Redis before a Flash Sale starts and running a reconciliation job to handle Redis/DB crash edge cases.

## 5. Rejected Alternatives
- **Option A (Direct DB Lock for 100K spike)**: Saturates HikariCP pools and PostgreSQL lock tables within 1 second.
- **Option B (`Redlock` around DB TX)**: Serializing network round-trips + DB commits inside a distributed lock reduces throughput to `<200 TPS` and is vulnerable to GC pause lock expiration without storage-level fencing tokens.
