# Performance Engineering Strategy — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-PERF-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Performance Engineering Philosophy

Performance engineering in this project is an **empirical, measurement-driven discipline**, never a marketing claim:
1. **No Unbacked Capacity Numbers**: Every latency (`p50`, `p95`, `p99`) or throughput (`RPS`) claim must link to a committed `k6` script, hardware specification, and raw summary JSON.
2. **Measure → Profile → Hypothesize → Optimize → Retest**: Never apply "optimizations" blindly without first proving where the bottleneck resides (CPU, lock contention, connection pool wait, GC pause, network I/O, or disk fsync).

---

## 2. Core Performance Metric Taxonomy

To avoid common industry confusion in interviews and reports, we strictly distinguish:

| Metric | Definition | Relationship / Formula |
| :--- | :--- | :--- |
| **MAU / DAU** | Monthly / Daily Active Users (unique humans visiting over 30d or 24h). | Business volume metric; determines storage growth and daily batch size, NOT instantaneous server load. |
| **CCU (Concurrent Users)** | Number of users actively maintaining a session or browsing at the same moment. | If `20,000 Peak CCU` each click once every `40 seconds` (think time), average arrival rate $\lambda = 20,000 / 40 = 500\text{ RPS}$. During a Flash Sale countdown (`T=0`), think time drops near zero, causing RPS to spike dramatically! |
| **VU (Virtual Users in `k6`)** | Concurrent simulated execution threads/coroutines in the load generator. | By Little's Law: $VU = \text{RPS} \times (\text{Response Time} + \text{Think Time})$. |
| **RPS (Requests Per Second)** | Rate of HTTP requests arriving at the system per second. | Edge ingress load metric. |
| **Throughput** | Rate of successfully completed business transactions/requests per second (or bytes/messages per second). | When the system is healthy, $\text{Throughput} \approx \text{RPS}$. Past the saturation knee point, RPS increases while Throughput plateaus or collapses! |
| **Latency (`p50`, `p95`, `p99`)** | Duration from request ingress to response completion at the 50th, 95th, and 99th percentiles. | Averages hide tail-latency stalls caused by GC pauses, lock waits, and cold caches. We optimize primarily for **`p95` and `p99`**. |
| **Error Rate** | Percentage of requests failing with `5xx`, unexpected `4xx`, or client timeouts. | Note: In a Flash Sale where 1,000 items are sold to 50,000 requests, `409 Conflict (SOLD_OUT)` is an **expected business rejection**, NOT a system error (`5xx`). `k6` custom checks distinguish business rejections from system failures. |

---

## 3. Target Workload Models

We model three realistic traffic distributions for `k6` benchmarking:

### Model W1: Normal Steady-State Commerce (`Load & Soak Test`)
- **Illustrative Scale Assumption**: `100K DAU`, normal daytime rate `100–250 RPS`, peak evening rate `500 RPS`.
- **Traffic Mix**:
  - `65%` Catalog Browse & Search (`GET /api/v1/products`, `GET /api/v1/products/{id}`)
  - `15%` Inventory & Promotion Check (`GET /api/v1/inventory/{sku}`, `GET /api/v1/promotions/active`)
  - `10%` Cart Operations (`POST/GET /api/v1/cart`)
  - `7%` Order Checkout & Payment Confirmation (`POST /api/v1/orders`, `POST /api/v1/payments/{id}/confirm`)
  - `3%` AI Shopping Assistant Queries (`POST /api/v1/ai/chat`)

### Model W2: Flash Sale Launch Spike (`Spike & Contention Test`)
- **Scenario**: Campaign with `allocated_quota = 1,000` units of a single hot SKU.
- **Traffic Pattern**: Warm-up at `100 RPS` (`GET` campaign page) → instantaneous spike at `T=0` to `2,000–5,000+ RPS` (scaled to hardware capacity) on `POST /api/v1/flash-sales/{id}/claim` over a `30–60s` window.
- **Primary Invariants**:
  1. Exactly `1,000` `202 Accepted` winning claims.
  2. All remaining requests receive `409 Conflict` (`SOLD_OUT` or `USER_LIMIT_EXCEEDED`) with `0%` unhandled `5xx` errors.
  3. PostgreSQL CPU remains `< 70%` during the spike because the Redis Lua gate filters out losers at the edge.

### Model W3: Breakpoint & Stress Ramp (`Capacity Discovery`)
- Stepwise ramp (`100 → 300 → 600 → 1000 → 1500+ RPS`) until `p99 > 1000ms` or `5xx Error Rate > 1%`, identifying the exact hardware saturation bottleneck.

---

## 4. Seven-Type `k6` Test Suite (`tests/performance/`)

1. **Smoke Test (`01-smoke.js`)**: `1–5 VUs` for `1m` verifying all endpoints return valid responses and telemetry pipelines record metrics.
2. **Load Test (`02-load-steady.js`)**: Sustained normal peak workload (`W1`) for `15m` validating `p95` and `p99` SLOs.
3. **Stress Test (`03-stress.js`)**: Pushes system to `1.5x–2x` target load for `15m` to verify graceful degradation and full recovery when load subsides.
4. **Spike Test (`04-flash-sale-spike.js`)**: Instantaneous `10x` surge (`W2`) testing the Flash Sale Redis Lua gate, Gateway rate limiter, and Kafka Outbox burst absorption.
5. **Soak / Endurance Test (`05-soak.js`)**: Sustained load over `2–4 hours` to detect connection leaks, memory leaks (Java Old Gen / .NET LOH growth), uncleaned Outbox table bloat, and disk growth.
6. **Breakpoint Test (`06-breakpoint.js`)**: `ramping-arrival-rate` executor incrementing RPS every 2 minutes until SLO breach to find the true hardware ceiling.
7. **Chaos + Load Test (`07-chaos-resilience.js`)**: Runs steady load (`W1`/`W2`) while injecting pod kills, Redis pause, or Kafka broker restart.

---

## 5. Deep Stack Observability & Profiling Telemetry

During every benchmark run, we capture and correlate metrics across all 6 infrastructure layers:

- **Java 21 / JVM (`Micrometer` + `JFR` / `Async-Profiler`)**:
  - Heap usage by generation (`Eden`, `Survivor`, `Old Gen`), GC pause duration (`jvm_gc_pause_seconds_max`), Virtual Thread pinned carrier events (`jdk.VirtualThreadPinned`), HikariCP active/pending connections (`hikaricp_connections_pending`), connection acquisition wait time.
- **.NET 10 / CLR (`OpenTelemetry.Instrumentation.Runtime` + `dotnet-counters`)**:
  - Gen 0/1/2 & LOH allocation rate (`process.runtime.dotnet.gc.allocations.size`), GC pause time %, ThreadPool queue length (`threadpool.queue.length`), active timers, Kestrel active connections.
- **PostgreSQL 17 (`pg_stat_statements` + `pg_stat_activity` + `postgres_exporter`)**:
  - Active vs. idle-in-transaction connections, row lock wait time (`wait_event_type = 'Lock'`), dead tuples vs. autovacuum rate on `stock_items` and `outbox_messages`, buffer cache hit ratio, `EXPLAIN (ANALYZE, BUFFERS)` query plans.
- **Redis 7.4 (`redis_exporter` + `SLOWLOG`)**:
  - Commands processed/sec, `EVALSHA` Lua execution time in microseconds, cache hit/miss ratio, used memory vs. `maxmemory`, evicted keys.
- **Apache Kafka (`JMX` / `kafka_exporter`)**:
  - Producer batch size & request latency, consumer group lag per partition (`kafka_consumergroup_lag`), Outbox relay throughput (`outbox_published_total`), DLQ count.
- **Kubernetes / Linux Node (`node_exporter` + `cAdvisor`)**:
  - Container CPU usage vs. CFS throttling (`container_cpu_cfs_throttled_periods_total`), working-set memory, network RX/TX saturation, disk IOPS & `await`.

---

## 6. Mandatory 10-Point Benchmark Report Template

Every performance experiment recorded in [`docs/performance/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/performance/) and [`docs/engineering-case-studies/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/engineering-case-studies/) MUST contain:
1. **Hardware Configuration** (Exact CPU model, vCPU count, RAM, disk type, network topology).
2. **Infrastructure & Runtime Configuration** (Replica counts, JVM/.NET flags, HikariCP/Npgsql pool sizes, Kafka partitions).
3. **Workload Definition** (Arrival rate, VU count, endpoint mix, payload size, dataset cardinality).
4. **Test Duration & Warm-up Window**.
5. **Exact `k6` Script & Command Executed**.
6. **Raw Results** (`p50`, `p90`, `p95`, `p99`, max latency, RPS achieved, HTTP status breakdown, business invariant SQL verification).
7. **Bottleneck Analysis** (Evidence from FlameGraphs, `pg_stat_statements`, HikariCP pending threads, or lock waits).
8. **Concrete Optimization Implemented** (Code, SQL index, lock strategy, or config diff).
9. **Retest Execution** under identical hardware and workload conditions.
10. **Before / After Comparison Table** proving measurable engineering improvement.
