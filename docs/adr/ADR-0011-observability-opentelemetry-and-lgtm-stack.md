# ADR-0011: Unified OpenTelemetry & LGTM Observability Architecture (`Metrics`, `Logs`, `Traces`)

- **Status:** `ACCEPTED` (Approved in M0.1)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In a 9-service polyglot platform (`Java 21`, `.NET 10`, `Python 3.12+`, `React`) communicating over HTTP/REST and asynchronous Kafka Outbox/Inbox streams, debugging a failed Flash Sale claim or stuck Saga without unified correlation across logs, metrics, and distributed traces is practically impossible. At the same time, running heavy commercial APMs or an Elasticsearch/ELK logging cluster (`>4 GiB` RAM) would overwhelm our `3.8 GiB` VM nodes.

## 2. Options Considered
- **Option A**: Uncorrelated stdout logs + per-language proprietary metrics without distributed tracing.
- **Option B**: ELK Stack (Elasticsearch + Logstash + Kibana) + Jaeger (`>4.5 GiB` RAM footprint).
- **Option C (Chosen)**: **Vendor-Neutral OpenTelemetry (`OTLP`) Instrumentation across Java/.NET/Python + Lightweight Grafana LGTM Stack (`OpenTelemetry Collector`, `Prometheus`, `Grafana`, `Loki`, `Tempo`)**.

## 3. Decision (`ACCEPTED`)
1. **Standardized W3C Trace Context Propagation**:
   - Every HTTP request entering `api-gateway` receives or preserves W3C `traceparent` + `X-Correlation-Id`.
   - Every Outbox event persisted to `outbox_messages` stores `traceparent` and `correlationId` in its JSONB `headers` column, and the Outbox Relay injects them into Kafka record headers so consumer spans (`inventory-service`, `payment-service`, `notification-service`) link into a single end-to-end trace tree.
2. **OpenTelemetry SDK in Every Runtime**:
   - **Java 21**: `micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp` + structured JSON logs with `trace_id`, `span_id`, `service.name`.
   - **.NET 10**: `OpenTelemetry.Extensions.Hosting` (`AspNetCore`, `HttpClient`, `EntityFrameworkCore`, `Runtime` instrumentation) exporting OTLP.
   - **Python 3.12+**: `opentelemetry-instrumentation-fastapi` + `httpx` + custom GenAI semantic convention spans (`gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `tool_call_name`).
3. **Collector & Storage Plane (`LGTM`)**:
   - All services push telemetry via OTLP (`gRPC :4317` / `HTTP :4318`) to a central **OpenTelemetry Collector**, which fans out metrics to **Prometheus**, logs to **Grafana Loki**, and traces to **Grafana Tempo**, visualized in **Grafana**.

## 4. Consequences & Trade-offs
- **Positive**: Complete correlation from a React `ProblemDetails` `traceId` directly to the exact Tempo span, Loki log line across Java/.NET/Python, and Prometheus metric spike; LGTM uses `~70%` less RAM than ELK.
- **Negative / Cost**: Requires propagating `traceparent` explicitly through the PostgreSQL `outbox_messages` table so async Kafka hops don't break trace continuity.

## 5. Rejected Alternatives
- **Option B (ELK Stack)**: Elasticsearch alone requires `2–4 GiB` JVM heap, exceeding a single VM's capacity.
