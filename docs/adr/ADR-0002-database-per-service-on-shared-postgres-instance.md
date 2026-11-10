# ADR-0002: Database-per-Service Isolation on a Consolidated PostgreSQL Instance

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Microservices architecture mandates **Database per Service** so no service can couple to another service's schema or bypass domain invariants. However, spinning up 7 separate PostgreSQL container/VM instances in local development or on a 3–4 VM on-prem cluster consumes `7 × (250–512 MiB)` of shared buffers and background worker memory before a single request is served.

## 2. Options Considered
- **Option A: Shared Database & Shared Schema** (all services connect to `commerce_db.public` with the same credentials).
- **Option B: 7 Separate PostgreSQL Container Instances** (`postgres-product:5432`, `postgres-order:5433`, etc.).
- **Option C: 1 PostgreSQL 17 Cluster Hosting 7 Strictly Isolated Databases (`*_db`) with Dedicated Least-Privilege DB Roles (`*_user`)**.

## 3. Decision
Adopt **Option C** for local Docker Compose and small-footprint on-prem Kubernetes deployments (while keeping JDBC/Npgsql connection strings 100% configurable per service so high-load databases like `inventory_db` or `order_db` can be pointed to dedicated PostgreSQL instances at any time without code changes).

An initialization script (`infrastructure/postgres/init-multi-db.sql`) creates:
- `product_db` owned by `product_svc_user` (`REVOKE ALL ON DATABASE ... FROM PUBLIC`)
- `customer_db` owned by `customer_svc_user`
- `order_db` owned by `order_svc_user`
- `inventory_db` owned by `inventory_svc_user`
- `payment_db` owned by `payment_svc_user`
- `promotion_db` owned by `promotion_svc_user`
- `ai_agent_db` (with `CREATE EXTENSION vector`) owned by `ai_agent_svc_user`

## 4. Consequences & Trade-offs
- **Positive**: Enforces cryptographic/permission-level Database-per-Service isolation (`order_svc_user` gets `FATAL: permission denied for database "inventory_db"` if misconfigured) while using only **1 PostgreSQL process tree (`~256–512 MiB` RAM)**.
- **Negative / Cost**: All 7 databases share the physical disk IOPS and `max_connections` ceiling of the host PostgreSQL instance (`max_connections = 200`, with each service capped at `HikariCP/Npgsql pool size = 10–15`).

## 5. Rejected Alternatives
- **Option A (Shared Schema)**: Violates Mandatory Rule #3 ("Never allow one service to directly access another service's database").
- **Option B (7 Containers)**: Wastes `>1.5 GiB` RAM on idle PostgreSQL background processes on a constrained VM.
