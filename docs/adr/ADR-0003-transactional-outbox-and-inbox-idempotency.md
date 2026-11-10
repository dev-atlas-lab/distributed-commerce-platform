# ADR-0003: Transactional Outbox Polling Relay & Idempotent Consumer Inbox

- **Status:** `ACCEPTED` (Approved in M0.1)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Services must update their own PostgreSQL database and publish domain/integration events to Apache Kafka without the dual-write vulnerability (losing events if the process crashes after DB commit, or emitting phantom events if the DB rollback occurs after Kafka send). Furthermore, Mandatory Rule #5 states we must never claim "exactly-once business processing" merely because Kafka supports transactions.

## 2. Options Considered
- **Option A: Synchronous Dual Write** (`repository.save()` followed by `kafkaTemplate.send()`).
- **Option B: Debezium CDC + Kafka Connect Cluster** tailing PostgreSQL WAL.
- **Option C: Transactional Outbox Table + `FOR UPDATE SKIP LOCKED` Polling Relay paired with Consumer Inbox Table (`PRIMARY KEY (event_id, consumer_group)`)**.

## 3. Decision (`ACCEPTED`)
Adopt **Option C**:
1. **Producer Side (Transactional Outbox)**: Domain state changes and `INSERT INTO outbox_messages` happen in the same local PostgreSQL ACID transaction. A background relay (`@Scheduled` in Spring Boot / `BackgroundService` in .NET) polls unprocessed rows (`WHERE processed_at IS NULL ORDER BY created_at ASC LIMIT 100 FOR UPDATE SKIP LOCKED`), publishes to Kafka with `acks=all` + `enable.idempotence=true`, and sets `processed_at = NOW()`.
2. **Consumer Side (Idempotent Inbox)**: Every Kafka consumer writes `INSERT INTO inbox_messages (event_id, consumer_group, event_type, processed_at) VALUES (...) ON CONFLICT DO NOTHING` inside the same local PostgreSQL transaction as its business state update. If `0` rows are inserted into `inbox_messages`, the duplicate message is acknowledged and skipped.

## 4. Consequences & Trade-offs
- **Positive**: Achieves deterministic **Effectively-Once Business State Mutation** over **At-Least-Once Messaging** with zero extra infrastructure containers (no Kafka Connect / Debezium JVM cluster required).
- **Negative / Cost**: Adds `1 INSERT + 1 UPDATE` per outgoing event on the producer DB and `1 INSERT` per incoming event on the consumer DB, plus a `50–200ms` polling interval. Requires a daily retention job to purge `processed_at < NOW() - INTERVAL '7 days'`.

## 5. Rejected Alternatives
- **Option A (Dual Write)**: Loses events during broker restarts or pod crashes.
- **Option B (Debezium CDC)**: Adds `~1 GiB` RAM for Kafka Connect and operational complexity that obscures the application-level mechanics of Outbox/Inbox during learning and interviews.
