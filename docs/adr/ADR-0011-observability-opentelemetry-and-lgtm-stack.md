# ADR-0011: Unified OpenTelemetry & LGTM Observability, Outbox Span Links & Dual-Gated Fault Injection

- **Status:** `ACCEPTED` (Core OpenTelemetry + LGTM Stack Accepted in `M0.1`; `CH-07` Outbox Span Links, Baggage Privacy & Dual-Gated Fault Injection `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In a 9-service polyglot platform (`Java 21`, `.NET 10`, `Python 3.12+`, `React`) communicating over HTTP/REST and asynchronous Kafka Outbox/Inbox streams, we need unified correlation across logs, metrics, and traces without running a heavy ELK cluster. Furthermore, in `M0.2` (`CH-07`), we must define:
1. How trace context (`traceparent`, `tracestate`) propagates across batched Outbox polling and Inbox consumption using both parent-child spans and **Span Links**.
2. How W3C `baggage` is sanitized to prevent PII leakage.
3. How deterministic fault injection hooks are isolated and locked out of production builds/deployments.

## 2. Options Considered
- **Option A**: Uncorrelated stdout logs + single batch-poller trace ID overwriting individual user order traces.
- **Option B**: ELK Stack + unguarded HTTP fault-injection headers.
- **Option C**: **OpenTelemetry (`OTLP`) + Grafana LGTM Stack + Per-Message Outbox Parent Restoration with Batch Span Links (`CH-07`) + Allowlisted W3C Baggage + Dual-Gated Fault Injection**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - All services export OTLP metrics, logs, and traces to the **OpenTelemetry Collector**, fanning out to **Prometheus**, **Grafana Loki**, and **Grafana Tempo**.
2. **Refined Trace Propagation, Privacy & Fault Injection (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-07`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Outbox/Inbox Trace Continuity**: At `INSERT INTO outbox_messages`, persist W3C `traceparent` and `tracestate` in `outbox_messages.headers` (`JSONB`). When the Outbox Relay polls a batch of $N$ rows, it creates a root `outbox.relay.batch` span, and for each message starts a `PRODUCER` span whose **parent** is the restored message `traceparent` and which carries a **SpanLink** to `outbox.relay.batch`. Kafka consumers extract `traceparent` from record headers so each Order's Saga trace appears as a single unbroken waterfall in Tempo.
   - **W3C Baggage Privacy (`INV-OBS-02`)**: Gateway and outbound HTTP clients enforce a strict `baggage` key allowlist (`correlation.id`, `test.run_id`, `fault.profile_id`), stripping any other keys and blocking PII from entering `baggage` or span attributes.
   - **Dual-Gated Fault Injection (`INV-OBS-03`)**: Fault injection interceptors are disabled by default via DI registration gates (`FAULT_INJECTION_ENABLED=false` in prod) AND require a verified `ADMIN_OPS` JWT with `scope: "chaos:inject"` when enabled in test/chaos environments.

## 4. Consequences & Trade-offs
- **Positive**: Preserves both per-order end-to-end Saga trace waterfalls and batch-poller operational telemetry via Span Links; prevents accidental PII leaks via W3C baggage; eliminates production fault-injection attack vectors.
- **Negative / Cost**: Requires explicit `TextMapPropagator` context reconstruction in the Outbox Relay loop (`~20` lines of code in Java and .NET).

## 5. Rejected Alternatives
- **Using the Outbox batch poll span as the parent of all 50 Kafka messages**: Rejected because it merges 50 unrelated customer orders into a single massive trace tree and breaks trace continuity from the original HTTP request.
