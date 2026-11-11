# ADR-0003: Transactional Outbox Relay, Idempotent Inbox & Fenced Two-Class HTTP Idempotency

- **Status:** `ACCEPTED` (Core Outbox/Inbox Pattern Accepted in `M0.1`; `CH-03` & `CH-04` Final Corrections `PROPOSED` in `M0.2.1`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Services must update their own PostgreSQL database and publish integration events to Apache Kafka without dual-write vulnerabilities. Additionally:
1. **HTTP Idempotency (`CH-03`)**: When a request with an external side effect (Redis Lua or Payment Gateway) times out, an expired lease alone must NEVER authorize re-executing the external side effect without first fencing stale workers (`lease_generation`) and reconciling whether the prior attempt already succeeded downstream.
2. **Outbox Relay & Consumer Ordering (`CH-04`)**: Multiple Outbox Relay pods polling concurrently with naive `FOR UPDATE SKIP LOCKED` can publish `(O1, v=2)` before `(O1, v=1)`. Furthermore, PostgreSQL `BIGSERIAL` sequence allocation order differs from transaction `COMMIT` visibility order across transactions, and consumers must handle missing version gaps (`incoming.aggregateVersion > last_applied + 1`) alongside stale versions (`<= last_applied`).

## 2. Options Considered
- **Option A**: Naive `FOR UPDATE SKIP LOCKED` across all rows + deleting idempotency keys on `5xx` or retrying blindly on lease expiry.
- **Option B**: Debezium CDC + Kafka Connect Cluster.
- **Option C**: **Head-of-Aggregate Serialized Outbox Relay + Consumer Version Continuity/Tombstone Gate (`CH-04`) + Fenced & Reconciled Two-Class HTTP Idempotency (`CH-03`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - Domain state changes and `INSERT INTO outbox_messages` commit atomically in a single local PostgreSQL transaction; consumers deduplicate via `inbox_messages (event_id, consumer_group)`.
2. **Refined `M0.2.1` Specifications (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-03`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **`CH-03` (Monotonic `lease_generation` Fencing & `RECONCILING` State)**:
     - Class B idempotency records assign an immutable `downstream_operation_id` at `lease_generation = 1`.
     - Local `lease_generation` fences local DB mutations (`WHERE lease_generation = :expectedGen`), while external side-effect deduplication relies on passing the immutable `downstream_operation_id` (and `lease_generation` for Redis Lua) to the downstream provider.
     - If a request times out (`UNKNOWN_RETRYABLE`) or its lease expires, a retrying worker increments `lease_generation` and enters **`RECONCILING`**. For Type I downstream systems (authoritative read-after-write + idempotent on `downstream_operation_id`), `NOT_FOUND` authorizes resuming with the same `downstream_operation_id`; for Type II (eventually consistent) downstream systems, `NOT_FOUND` keeps polling in `RECONCILING` and escalates to `MANUAL_INTERVENTION_REQUIRED` after timeout (`INV-IDEM-03`).
   - **`CH-04` (3-Phase Lease-Claimed Outbox Serialization & Sequence-Gap Handling)**:
     - To avoid holding PostgreSQL row locks across Kafka network I/O, Outbox Relay workers use a **3-Phase Claim-Publish-Complete** protocol: Phase 1 (`<2ms` DB TX) claims up to 25 unlocked aggregates (`NOT EXISTS` any active `'PUBLISHING'` lease on the same `aggregate_id`, guarded by `pg_try_advisory_xact_lock(hashtext(aggregate_id))`) and sets `relay_status = 'PUBLISHING', relay_lease_until = NOW() + 30s`; Phase 2 publishes each aggregate's events sequentially to Kafka (`acks=all`, `enable.idempotence=true`, aborting the aggregate batch on first error so $v+1$ never leapfrogs $v$); Phase 3 (`<2ms` DB TX) marks published rows `processed_at = NOW()`.
     - Stateful consumers enforce `aggregateVersion` continuity: `<= last_applied` is ignored as stale; `== last_applied + 1` is applied; `> last_applied + 1` applies a Terminal Tombstone (if cancellation) or routes delta events to `.retry.1m` (`SEQUENCE_GAP_DETECTED`) until the missing version arrives.

## 4. Consequences & Trade-offs
- **Positive**: Eliminates multi-pod Outbox ordering inversions; prevents zombie worker overwrites and duplicate external side effects after timeouts.
- **Negative / Cost**: Requires 1 downstream status query during the rare `RECONCILING` recovery path after a network timeout.

## 5. Rejected Alternatives
- **Re-executing external calls immediately upon lease expiry (`M0.2` draft)**: Rejected in `M0.2.1` because an expired lease does not prove the prior worker's external call failed.
