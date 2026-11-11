# ADR-0003: Transactional Outbox Relay, Consumer-Boundary Ordering & Fenced Two-Class HTTP Idempotency

- **Status:** `DESIGN_ACCEPTED` (Frozen in `M0.3`; `HD-04` Generation-Scoped `transactional.id` Broker Fencing `SUPERSEDED` by Simplified Consumer-Boundary Ordering Contract)
- **Date:** 2026-04-11
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Services must update their own PostgreSQL database and publish integration events to Apache Kafka without dual-write vulnerabilities. Additionally:
1. **HTTP Idempotency (`CH-03`)**: When a request with an external side effect (Redis Lua or Payment Gateway) times out, an expired lease alone must NEVER authorize re-executing the external side effect without first fencing stale workers (`lease_generation`) and reconciling whether the prior attempt already succeeded downstream.
2. **Outbox Relay & Consumer Ordering (`CH-04`)**: Multiple Outbox Relay workers polling concurrently can experience JVM/GC pauses or lease expiration. Earlier iterations (`M0.2.4` / `M0.2.5`, `HD-04`) explored generation-scoped Kafka `transactional.id`s (`<service>-outbox-shard-<shard>-gen-<G>`) to guarantee strict append order in Kafka. However, because downstream consumers already enforce atomic `inbox_messages` deduplication and strict sequential `aggregate_version` validation (`incoming.version == last_applied_version + 1`), enforcing strict broker-level fencing across generations adds significant operational and coordinator overhead without improving end-to-end aggregate state correctness.

## 2. Options Considered
- **Option A**: Naive `FOR UPDATE SKIP LOCKED` across all rows + deleting idempotency keys on `5xx` or retrying blindly on lease expiry.
- **Option B**: Generation-scoped Kafka `transactional.id` (`<service>-outbox-shard-<shard>-gen-<G>`) with predecessor epoch loop fencing (`HD-04` — `M0.2.5`).
- **Option C (Chosen in `M0.3`)**: **At-Least-Once Partitioned Outbox Relay (`DISTINCT ON (aggregate_id)`) + PostgreSQL Lease Coordination + Consumer-Boundary Version Gate (`CH-04`) + Fenced & Reconciled Two-Class HTTP Idempotency (`CH-03`)**.

## 3. Decision (`DESIGN_ACCEPTED`)

### 3.1 Transactional Outbox & Simplified `CH-04` Ordering Contract
1. **Atomic Local Commit**: Domain state changes and `INSERT INTO outbox_messages` commit atomically in a single local PostgreSQL transaction. Every outbox message carries an immutable `event_id`, `aggregate_type`, `aggregate_id`, `aggregate_version` (monotonic per aggregate instance, $1, 2, 3, \dots$), and `partition_key = aggregate_id`.
2. **Head-of-Aggregate Polling (`DISTINCT ON (aggregate_id)`)**:
   - Each Outbox Relay polling cycle selects at most **one** unpublished row per `aggregate_id`—specifically the lowest unpublished `aggregate_version`:
     ```sql
     SELECT DISTINCT ON (aggregate_id)
            id, event_id, aggregate_type, aggregate_id, aggregate_version,
            partition_key, topic, payload, headers, created_at
     FROM outbox_messages
     WHERE published_at IS NULL
       AND shard_id = $1
     ORDER BY aggregate_id, aggregate_version ASC
     LIMIT $2;
     ```
   - Relay workers coordinate shard ownership via `outbox_relay_shards (shard_id, owner_id, lease_epoch, lease_expires_at)` in PostgreSQL and mark rows published with `WHERE id = ANY($1) AND published_at IS NULL`.
3. **Explicit Guarantee Separation (No False Broker-Fencing Claim)**:
   - **Kafka Delivery Order (`At-Least-Once`, Best-Effort Partition Order)**: Standard idempotent Kafka producers (`enable.idempotence=true`, `acks=all`) publish with `key = aggregate_id`. **A PostgreSQL shard lease does NOT fence an already-running paused producer at the Kafka broker.** If a relay worker pauses past `lease_expires_at`, duplicate delivery or a temporary version inversion (`v+1` arriving before `v`) on the Kafka partition is possible and explicitly tolerated.
   - **Consumer Application Order (`Strictly Sequential per Aggregate`)**: Consumers enforce an atomic `inbox_messages (message_id, consumer_group)` check + aggregate version check in a single local transaction:
     - `incoming.version <= last_applied_version`: Duplicate or stale delivery -> **idempotent no-op** (acknowledged and ignored).
     - `incoming.version == last_applied_version + 1`: Next expected version -> **applied atomically** and `last_applied_version` incremented.
     - `incoming.version > last_applied_version + 1`: Out-of-order version gap -> **buffered/deferred for bounded retry** (`SEQUENCE_GAP_DETECTED`); **never applied early and never skipped**.
   - **Aggregate State Correctness (`Deterministic`)**: Because the consumer boundary enforces exact sequential application (`v = 1, 2, 3...`), aggregate projections and Saga transitions remain 100% deterministic under relay pauses, retries, and rebalances.

### 3.2 Fenced Two-Class HTTP Idempotency (`CH-03`)
1. **Class A (Local-Only Mutations)**: Command handler, domain mutation, `outbox_messages` insert, and `idempotency_records` (`status = COMPLETED`) commit in a single local PostgreSQL transaction.
2. **Class B (External / Type II Downstream Side Effects)**:
   - Assigns an immutable `downstream_operation_id` at initial claim creation (`lease_generation = 1`).
   - All local state updates check `WHERE idempotency_key = $1 AND lease_generation = $2`.
   - If a worker crashes or times out (`lease_expires_at < NOW()`), the recovery worker atomically increments `lease_generation = lease_generation + 1`, transitions `status = 'RECONCILING'`, and queries downstream status using the immutable `downstream_operation_id` before deciding whether to complete, fail, or re-invoke with the same `downstream_operation_id`.
   - If downstream state remains ambiguous past `15 minutes`, the record transitions to `MANUAL_INTERVENTION_REQUIRED` and emits an operational alert.

## 4. Consequences & Trade-offs
- **Positive**: Eliminates dynamic `transactional.id` coordinator bloat on Kafka while preserving strict per-aggregate state correctness at the consumer boundary; prevents zombie worker overwrites and duplicate external side effects after timeouts.
- **Negative / Cost**: Requires consumers to maintain `last_applied_version` on replicated aggregates/read-models and defer out-of-order (`> last_applied_version + 1`) events when a relay lease handoff overlaps.

## 5. Rejected / Superseded Alternatives
- **Option B (`HD-04` Generation-Scoped `transactional.id` Broker Fencing)**: Marked `SUPERSEDED` in `M0.3` because consumer-side version gating (`incoming.version == last_applied_version + 1`) already guarantees aggregate state correctness without broker-level epoch loops.
- **Option A (Re-executing external calls immediately upon lease expiry)**: Rejected because an expired lease does not prove the prior worker's external call failed.
