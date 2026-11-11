# Local Development Infrastructure (`deploy/local/`)

This directory contains the reproducible Docker Compose stack (`PostgreSQL 17 + pgvector`, `Redis 7.4`, and `Apache Kafka 3.8.1 KRaft`) and database bootstrap script for `M1.1`:

- [`docker-compose.yml`](file:///home/anhltn/projects/distributed-commerce-platform/deploy/local/docker-compose.yml): Pinned local infrastructure definition with health checks, persistent named volumes (`commerce_postgres_data`, `commerce_redis_data`, `commerce_kafka_data`), dedicated network (`commerce_local_net`), and mandatory `.env` variable interpolation.
- [`postgres/init-multi-db.sh`](file:///home/anhltn/projects/distributed-commerce-platform/deploy/local/postgres/init-multi-db.sh): Initializes the 8 isolated per-service PostgreSQL 17 databases, enables `pg_trgm` (`catalog_db`) and `vector` (`ai_agent_db`), enforces `NOSUPERUSER` on all roles, and provisions the `ADR-0005` 4-role separation in `promotion_db` (`promotion_proc_owner`, `promotion_migrator`, `promotion_app_role`, `promotion_dba_admin`).

## Quick Start (From Repository Root)

```bash
cp .env.example .env
docker compose --env-file .env -f deploy/local/docker-compose.yml up -d --wait
./scripts/verify-local-infra.sh
```

See [`docs/runbooks/LOCAL_DEVELOPMENT.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/runbooks/LOCAL_DEVELOPMENT.md) and [`docs/architecture/LOCAL_INFRASTRUCTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/LOCAL_INFRASTRUCTURE.md) for full details.
