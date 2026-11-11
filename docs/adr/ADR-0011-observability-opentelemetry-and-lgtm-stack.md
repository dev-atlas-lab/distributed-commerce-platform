# ADR-0011: Unified OpenTelemetry & LGTM Observability, Outbox Span Links, Baggage Zero-Trust & Server-Registered Fault Profiles

- **Status:** `DESIGN_ACCEPTED` (Core OpenTelemetry + LGTM Stack Accepted in `M0.1`; `CH-07` Outbox Span Links, Baggage Zero-Trust & Server-Allowlisted Fault Profiles Frozen as `DESIGN_ACCEPTED` in `M0.3`)
- **Date:** 2026-04-11
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our 9-service polyglot platform (`Java 21`, `.NET 10`, `Python 3.12+`, `React`), we need unified correlation across logs, metrics, and traces without running a heavy ELK cluster. Furthermore (`CH-07`), we must guarantee:
1. Seamless trace continuity across batched Outbox polling and Kafka Inbox consumption using per-message parent restoration and **Span Links**.
2. Strict zero-trust handling of W3C `baggage` (never used for authorization or PII).
3. Production-safe fault injection restricted to server-registered fault profiles (`fault.profile_id`) with target allowlists and mandatory audit logging.

## 2. Options Considered
- **Option A**: Uncorrelated stdout logs + batch trace overwriting user traces.
- **Option B**: Client-supplied raw fault parameters in HTTP headers (`X-Fault-Inject: delay=10000`).
- **Option C**: **OpenTelemetry (`OTLP`) + Grafana LGTM Stack + Per-Message Outbox Parent Restoration with Batch Span Links + Zero-Trust Allowlisted W3C Baggage + Dual-Gated Server-Registered Fault Profiles (`CH-07`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - All services export OTLP metrics, logs, and traces to the **OpenTelemetry Collector**, fanning out to **Prometheus**, **Grafana Loki**, and **Grafana Tempo**.
2. **Validated `M0.2.1` Specifications (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-07`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Outbox/Inbox Trace Continuity (`INV-OBS-01`)**: `outbox_messages.headers` stores W3C `traceparent` and `tracestate`. Each Kafka publish span restores the message's `traceparent` as its parent and attaches a **SpanLink** to the `outbox.relay.batch` poll span.
   - **W3C Baggage Is Never Authorization (`INV-OBS-02`)**: Gateway enforces a strict `baggage` key allowlist (`correlation.id`, `test.run_id`, `fault.profile_id`), strips all other keys, and prohibits services from reading identity, roles, or PII from `baggage`.
   - **Server-Registered Fault Profiles & Fail-Closed Production Exclusion (`INV-OBS-03`)**:
     - **Fail-Closed Startup Guard**: If `ENVIRONMENT == 'production'` (or `PRODUCTION_LOCK == 'true'`) and `FAULT_INJECTION_ENABLED == 'true'`, the application throws `FatalSecurityConfigurationException` and **aborts startup immediately**.
     - Fault injection is completely unavailable in production (`FAULT_INJECTION_ENABLED=false` excludes the interceptor/beans from DI registration at startup).
     - When enabled in non-prod chaos environments (`FAULT_INJECTION_ENABLED=true` and `ENVIRONMENT IN ('development', 'test', 'chaos')`), callers must present a verified `HUMAN_PRINCIPAL` `ADMIN_OPS` JWT with `scope: "chaos:inject"` and can only reference pre-configured **Server-Side Fault Profile IDs** (`fault-profiles.yaml`) that enforce target service/endpoint allowlists and duration caps, emitting a mandatory `CHAOS_FAULT_PROFILE_ACTIVATED` audit log.

## 4. Consequences & Trade-offs
- **Positive**: Complete end-to-end Saga trace visibility in Tempo; zero PII leakage via W3C baggage; zero arbitrary fault-injection attack surface.
- **Negative / Cost**: New chaos scenarios require adding a named profile entry in `fault-profiles.yaml` rather than passing ad-hoc raw durations from the client.

## 5. Rejected Alternatives
- **Option B (Client-supplied raw delay/error parameters in headers)**: Rejected in `M0.2.1` because server-side profile allowlisting is much safer and more reproducible.
