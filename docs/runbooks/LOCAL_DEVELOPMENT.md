# Local Development & Infrastructure Runbook (`LOCAL_DEVELOPMENT.md`)

**Milestone:** `M1.1` — Local Infrastructure Bootstrap
**Last Updated:** 2026-04-11

This runbook provides step-by-step instructions to configure, start, verify, inspect, reset, and troubleshoot the local infrastructure stack (`PostgreSQL 17`, `Redis 7.4`, and `Apache Kafka 3.8.1 KRaft`) and polyglot application foundation.

---

## 1. Prerequisites

Ensure the following tools are installed on your Linux/macOS/WSL2 workstation:
- **Docker Engine** (`24.0+`, verified with `29.1.3`) and **Docker Compose v2** (`2.20+`, verified with `2.40.3`)
- **PostgreSQL Client (`psql`)** and **Redis CLI (`redis-cli`)** (used by [`scripts/verify-local-infra.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/verify-local-infra.sh))
- **Java 21 LTS** (`OpenJDK 21`) & **Apache Maven** (`3.6+`)
- **.NET 10 SDK** (`10.0.100+`)
- **Python 3.12+** & **`uv`**

Ensure `$HOME/.local/bin` and `$HOME/.dotnet` are in your `PATH`:
```bash
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"
```

---

## 2. Credentials & Environment File Setup

No credentials are hardcoded in [`deploy/local/docker-compose.yml`](file:///home/anhltn/projects/distributed-commerce-platform/deploy/local/docker-compose.yml). Compose uses mandatory `${VAR:?error}` interpolation and will refuse to start if `.env` is missing.

1. Copy the template environment file at the repository root:
   ```bash
   cp .env.example .env
   ```
2. *(Optional)* Customize local passwords or ports in `.env`.
   > **Security Rule:** `.env` is ignored by [`.gitignore`](file:///home/anhltn/projects/distributed-commerce-platform/.gitignore). Never commit `.env` or real API keys to Git.

---

## 3. Infrastructure Ports & Connection Reference

| Service | Host Address | Internal Docker Address | Credentials Variable in `.env` |
| :--- | :--- | :--- | :--- |
| **PostgreSQL 17** | `localhost:5432` | `commerce-postgres:5432` | Per-service user/password (`CATALOG_DB_USER`, `ORDER_DB_USER`, `PROMOTION_APP_USER`, etc.) |
| **Redis 7.4** | `localhost:6379` | `commerce-redis:6379` | `REDIS_PASSWORD` |
| **Kafka 3.8.1 (KRaft)** | `localhost:9092` (`EXTERNAL`) | `commerce-kafka:29092` (`INTERNAL`) | `PLAINTEXT` (local dev only) |

---

## 4. Standard Lifecycle Commands

Run all commands from the repository root (`/home/anhltn/projects/distributed-commerce-platform`):

### 4.1 Start Infrastructure & Wait for Health Checks
```bash
docker compose --env-file .env -f deploy/local/docker-compose.yml up -d --wait
```

### 4.2 Run Automated Infrastructure Verification (`M1.1`)
Executes readiness checks, 8-database isolation & `NOSUPERUSER` assertions, `promotion_db` 4-role & schema lockdown assertions, Redis `NOAUTH`/`PING`/AOF checks, Kafka external listener (`localhost:9092`) topic/produce/consume checks, and container restart persistence checks:
```bash
./scripts/verify-local-infra.sh
```

### 4.3 Run Polyglot Source Foundation Build & Tests
```bash
./scripts/verify-foundation.sh
```

### 4.4 Inspect Container Status & Logs
```bash
# Check container statuses and health probes
docker compose --env-file .env -f deploy/local/docker-compose.yml ps

# Tail logs for all containers (or specify postgres / redis / kafka)
docker compose --env-file .env -f deploy/local/docker-compose.yml logs -f
docker compose --env-file .env -f deploy/local/docker-compose.yml logs -f kafka
```

### 4.5 Stop Infrastructure (Preserving Named Volumes)
```bash
docker compose --env-file .env -f deploy/local/docker-compose.yml down
```

### 4.6 Full Reset (Wipe All Persistent Volumes & Re-Initialize from Scratch)
> **Note:** PostgreSQL only executes `/docker-entrypoint-initdb.d/01-init-multi-db.sh` when the data volume `commerce_postgres_data` is empty. If you change database/role variables in `.env`, perform a full volume reset:
```bash
docker compose --env-file .env -f deploy/local/docker-compose.yml down -v
docker compose --env-file .env -f deploy/local/docker-compose.yml up -d --wait
./scripts/verify-local-infra.sh
```

---

## 5. Troubleshooting Guide

1. **`required variable ... is missing a value` when running `docker compose`**:
   - Ensure you pass `--env-file .env` from the repository root (or that `.env` exists in the repository root, as `deploy/local/docker-compose.yml` is located two levels deep).
2. **PostgreSQL password or role changes in `.env` did not take effect**:
   - `/docker-entrypoint-initdb.d/01-init-multi-db.sh` runs only on initial volume creation. Run `docker compose --env-file .env -f deploy/local/docker-compose.yml down -v` and then `up -d --wait`.
3. **Kafka `CLUSTER_ID` mismatch after changing `KAFKA_CLUSTER_ID` in `.env`**:
   - The formatted KRaft storage directory in `commerce_kafka_data` stores `meta.properties` bound to the initial `CLUSTER_ID`. Run `docker compose --env-file .env -f deploy/local/docker-compose.yml down -v` to reformat the volume.
4. **Port conflict on `5432`, `6379`, or `9092`**:
   - Check if a host-level `postgresql` or `redis-server` systemd service is already listening (`ss -tulpn | grep -E '5432|6379|9092'`), or override `POSTGRES_PORT`, `REDIS_PORT`, or `KAFKA_EXTERNAL_PORT` in `.env`.
