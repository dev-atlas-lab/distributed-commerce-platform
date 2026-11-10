# ADR-0003: Transactional Outbox Polling Relay, Idempotent Consumer Inbox & Two-Class HTTP Idempotency

- **Status:** `ACCEPTED` (Core Outbox/Inbox Pattern Accepted in `M0.1`; `CH-03` & `CH-04` Edge-Case Refinements `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Services must update their own PostgreSQL database and publish domain/integration events to Apache Kafka without the dual-write vulnerability. Additionally:
1. HTTP mutation endpoints (`POST /orders`, `POST /flash-sales/{id}/claim`, `POST /payments`) must handle concurrent duplicate requests, payload mismatches, and unknown outcomes after network timeouts (`CH-03`).
2. Kafka consumers must handle duplicate deliveries (`At-Least-Once`) and out-of-order events caused by non-blocking retry topics or DLQ replays (`CH-04`).

## 2. Options Considered
- **Option A**: Synchronous Dual Write + Naive `5xx` idempotency key deletion.
- **Option B**: Debezium CDC + Kafka Connect Cluster.
- **Option C**: **Transactional Outbox (`FOR UPDATE SKIP LOCKED` + `outbox_sequence`) + Consumer Inbox (`PRIMARY KEY (event_id, consumer_group)`) + Two-Class HTTP Idempotency State Machine (`CH-03`) + Aggregate Version / Tombstone Guards (`CH-04`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - **Producer Side (Transactional Outbox)**: Domain state changes and `INSERT INTO outbox_messages` happen in the same local PostgreSQL ACID transaction. A background relay polls unprocessed rows (`WHERE processed_at IS NULL ORDER BY outbox_sequence ASC LIMIT 100 FOR UPDATE SKIP LOCKED`), publishes to Kafka with `acks=all` + `enable.idempotence=true`, and sets `processed_at = NOW()`.
   - **Consumer Side (Idempotent Inbox)**: Every Kafka consumer writes `INSERT INTO inbox_messages (event_id, consumer_group, event_type, processed_at) VALUES (...) ON CONFLICT DO NOTHING` inside the same local PostgreSQL transaction as its business state update.
2. **Refined Edge-Case Specifications (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **`CH-03` (Two-Class HTTP Idempotency)**: Never blindly delete idempotency records on `5xx` if an external call (Redis Lua or Payment Gateway) was initiated. Persist `downstream_operation_id` (`claim_id` / `attempt_id`) in `STARTED` state, transition to `UNKNOWN_RETRYABLE` on timeout, and resume with the **same** `downstream_operation_id` on retry. Validate canonical JSON `SHA-256` payload hashes (`422` on mismatch, `409` while `STARTED` lease is active).
   - **`CH-04` (Aggregate Sequence & Tombstone Guard)**: Every event envelope carries `aggregateVersion`. Out-of-order cancellations arriving before creation insert a `CANCELLED_TOMBSTONE` (`RELEASED`) row so delayed creation events from `.retry.1m` are safely ignored.

## 4. Consequences & Trade-offs
- **Positive**: Achieves deterministic **Effectively-Once Business State Mutation** over **At-Least-Once Messaging**, survives out-of-order retry inversions, and prevents double-charges after gateway timeouts.
- **Negative / Cost**: Adds `1 INSERT + 1 UPDATE` per outgoing event and requires a daily retention purge for `outbox_messages`, `inbox_messages`, and `idempotency_records`.

## 5. Rejected Alternatives
- **Deleting idempotency records on every `5xx` (`M0.1` draft)**: Rejected in `M0.2` because a `504 Gateway Timeout` after an external side effect has started would allow a retry to execute the side effect a second time.
