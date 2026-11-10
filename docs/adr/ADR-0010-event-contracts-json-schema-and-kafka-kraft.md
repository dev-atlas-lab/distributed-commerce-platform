# ADR-0010: Service Communication, OpenAPI 3.1 REST & Kafka KRaft JSON Schema Event Contracts

- **Status:** `ACCEPTED` (Approved in M0.1)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Our polyglot microservices (`Java 21`, `.NET 10`, `Python 3.12+`) communicate synchronously for edge queries/commands and asynchronously for multi-service Saga workflows, Flash Sale order materialization, and notifications. We must establish strict, versioned contracts for both communication modes without introducing heavy ZooKeeper or JVM Schema Registry containers.

## 2. Options Considered
- **Option A**: Ad-hoc unversioned JSON payloads + Kafka with ZooKeeper + Confluent Schema Registry.
- **Option B (Chosen)**: **Contract-First OpenAPI 3.1 + RFC 9457 `ProblemDetails` for Sync REST, and Apache Kafka 3.8+ (`KRaft` Mode) + CloudEvents-Style JSON Envelope validated by JSON Schema Draft 2020-12 in `docs/event-contracts/`**.

## 3. Decision (`ACCEPTED`)
1. **Synchronous Communication (`HTTP/REST`)**:
   - Governed by versioned **OpenAPI 3.1** specs in `docs/api-contracts/*.openapi.yaml` (`/api/v1/*`).
   - All errors across Java, .NET, and Python return **RFC 9457 `ProblemDetails`** (`application/problem+json`) containing `errorCode`, `traceId`, and `timestamp`.
   - Synchronous service-to-service chains are strictly bounded (`depth <= 2`) with explicit timeouts (`1.5s`), Resilience4j/Polly circuit breakers, and `Idempotency-Key` headers on mutations.
2. **Asynchronous Event Streaming (`Apache Kafka KRaft`)**:
   - Run **Apache Kafka 3.8+ in KRaft mode** (`process.roles=broker,controller`), eliminating ZooKeeper.
   - All events use the standardized **JSON Event Envelope** (`eventId`, `eventType`, `eventVersion`, `source`, `aggregateType`, `aggregateId`, `occurredAt`, `correlationId`, `causationId`, `payload`) validated against **JSON Schema (Draft 2020-12)** in `docs/event-contracts/`.

## 4. Consequences & Trade-offs
- **Positive**: Saves `~800 MiB` RAM (no ZooKeeper + no Schema Registry container); enforces contract-first discipline across all 3 backend languages and React frontend.
- **Negative / Cost**: Requires automated contract validation tests in CI (`DCP-M1-007`) to ensure producers and consumers never drift from `docs/api-contracts/` and `docs/event-contracts/`.

## 5. Rejected Alternatives
- **Option A**: Unversioned JSON leads to silent runtime deserialization failures across Java/.NET/Python; ZooKeeper is deprecated.
