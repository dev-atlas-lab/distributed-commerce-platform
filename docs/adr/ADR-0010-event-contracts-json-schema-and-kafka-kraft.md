# ADR-0010: Apache Kafka KRaft Mode & Monorepo JSON Schema Event Contracts

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Our event-driven backbone connects `Java 21`, `.NET 10`, and `Python 3.12+` services. We must decide:
1. Kafka cluster metadata mode: legacy `ZooKeeper` vs. modern **`KRaft` (KIP-500)**.
2. Event serialization & schema governance: running a dedicated `Confluent Schema Registry + Avro/Protobuf` container vs. **CloudEvents-style JSON Envelope validated against versioned JSON Schema (Draft 2020-12) files in `docs/event-contracts/`**.

## 2. Options Considered
- **Option A**: Kafka + ZooKeeper + Confluent Schema Registry + Avro.
- **Option B**: **Apache Kafka 3.8+ in `KRaft` mode** + **UTF-8 JSON Envelope with monorepo-governed JSON Schema contracts (`docs/event-contracts/*.schema.json`) validated in CI and contract tests**.

## 3. Decision
Adopt **Option B**:
1. Run **Apache Kafka 3.8+ in KRaft mode** (`process.roles=broker,controller`), completely eliminating ZooKeeper.
2. Serialize events as UTF-8 JSON conforming to our standard event envelope (`eventId`, `eventType`, `eventVersion`, `source`, `aggregateId`, `occurredAt`, `correlationId`, `causationId`, `payload`) and validate every producer/consumer against versioned **JSON Schema** files in [`docs/event-contracts/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/event-contracts/).
3. Enforce backward-compatible schema evolution rules (additive optional fields only inside `.v1`; breaking changes require a new `.v2` schema and event type).

## 4. Consequences & Trade-offs
- **Positive**: Saves `~800 MiB` RAM (no ZooKeeper + no Schema Registry JVM container); events in `outbox_messages (JSONB)` and Kafka topics are directly inspectable via SQL and CLI without custom binary deserializers; native cross-language support in Jackson (Java), `System.Text.Json` (.NET), and Pydantic (Python).
- **Negative / Cost**: JSON payloads are larger on the wire than binary Avro/Protobuf (`~200–400 bytes` per event, easily compressed via `compression.type=lz4` or `snappy` on Kafka producers).

## 5. Rejected Alternatives
- **Option A (ZooKeeper + Schema Registry)**: ZooKeeper is deprecated/removed in modern Kafka; running Schema Registry adds unnecessary container memory overhead for a monorepo where all producer and consumer schemas are versioned and tested together in Git.
