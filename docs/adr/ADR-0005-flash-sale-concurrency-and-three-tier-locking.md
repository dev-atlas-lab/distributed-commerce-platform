# ADR-0005: Flash Sale Concurrency Architecture, Reservation Expiration & Fenced Reconciliation

- **Status:** `ACCEPTED` (`Q4 Option A` Accepted in `M0.1`; `CH-01` PostgreSQL Tombstone Fencing before Redis Restock `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our Flash Sale scenario (`100,000` users competing for `1,000` units):
1. Direct PostgreSQL row locking collapses under 100K RPS, and JPA/EF Optimistic Locking (`@Version`) triggers a 99% abort storm.
2. When Redis Lua (`flash_sale_claim.lua`) decrements stock, a crash or network stall before PostgreSQL commits creates split-brain uncertainty. **Crucially, a 30-second timeout never proves a PostgreSQL transaction did not commit** (a stalled packet or GC pause could commit at $T=32\text{s}$ after a naive reconciler already restored Redis stock at $T=30\text{s}$, causing an oversell).
3. Under `Q4 Option A` (`ACCEPTED`), expired unpaid reservations return stock to the active Redis campaign pool, requiring strict protection against double-release when expiration and user cancellation race.

## 2. Options Considered
- **Option A**: PostgreSQL Pessimistic Row Lock (`SELECT ... FOR UPDATE`) for all traffic.
- **Option B**: Naive 30-second Redis timeout rollback without database fencing (`M0.1` draft).
- **Option C**: **3-Tier Concurrency Architecture + `Q4 Option A` Active-Pool Expiry Return + Two-Phase Claim Lease with PostgreSQL Tombstone Fencing (`ABANDONED_FENCED`) Before Redis Restock (`CH-01`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - **Tier 1 (Flash Sale Hot Gate)**: Redis Atomic Lua script (`flash_sale_claim.lua`) enforces campaign window, per-user quota, and stock decrement (`<10ms`), followed by PostgreSQL `FlashSaleClaim` + Outbox `FlashSaleSlotClaimed`.
   - **Tier 2 (`Q4 Option A` Reservation Expiry)**: Unpaid expired Flash Sale reservations return stock to the active Redis pool if the campaign is still `ACTIVE`, or reconcile back to warehouse `available_qty` if `ENDED`.
   - **Tier 3 (Standard Stock)**: Single-statement conditional atomic SQL (`UPDATE stock_items SET available_qty = available_qty - :qty ... WHERE sku_id = :skuId AND available_qty >= :qty`) ordered by `sku_id ASC`.
   - **Tier 4 (Low-Contention Entities)**: `@Version` Optimistic Concurrency Control.
2. **Refined Claim Lifecycle & Fenced Reconciliation (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-01`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **6-State Claim Machine**: `REDIS_INTENT_LEASED -> CLAIMED_RESERVED -> ORDER_MATERIALIZED -> PAYMENT_CONFIRMED | CANCELLED | EXPIRED | ABANDONED_FENCED`.
   - **Write-Fence Before Restock (`INV-FS-02`)**: Before the Reconciler returns an unacknowledged expired Redis intent lease to `RedisAvailableStock`, it MUST first execute `INSERT INTO flash_sale_claims (claim_id, status='ABANDONED_FENCED', ...) ON CONFLICT (claim_id) DO NOTHING` in PostgreSQL. If a delayed zombie transaction later tries to commit `CLAIMED_RESERVED` for that `claim_id`, PostgreSQL rejects it via primary-key conflict. If `ON CONFLICT` reveals the row was already committed as `CLAIMED_RESERVED`, the Reconciler simply clears the Redis intent lease without restocking.
   - **At-Most-Once Restock Guard (`INV-FS-03`)**: `flash_sale_release.lua` executes `HSETNX flashsale:{campaignId}:sku:{skuId}:released_claims {claimId} 1` before `INCRBY stock`, making concurrent expiry + cancellation or duplicate Kafka deliveries 100% idempotent.

## 4. Consequences & Trade-offs
- **Positive**: Mathematically eliminates split-brain overselling between Redis and PostgreSQL even under arbitrary network stalls or GC pauses.
- **Negative / Cost**: Requires 1 PostgreSQL tombstone `INSERT` per abandoned Redis intent lease (`<0.01%` crash path) before returning stock to Redis.

## 5. Rejected Alternatives
- **Option B (Unfenced 30-second timeout rollback)**: Rejected in `M0.2` because timeout does not imply transaction abort in an asynchronous network.
