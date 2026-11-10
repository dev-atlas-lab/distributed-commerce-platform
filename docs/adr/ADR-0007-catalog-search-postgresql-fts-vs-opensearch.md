# ADR-0007: Phased Product Catalog Search: PostgreSQL 17 FTS + `pg_trgm` Benchmark Gate before OpenSearch

- **Status:** `ACCEPTED` (Approved in M0.1 — Q6 Start with PG FTS & Benchmark Before Considering OpenSearch)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
The platform requires fast product catalog search supporting keyword queries, prefix/typo tolerance, category hierarchy filtering, price range filtering, attribute facets, and sorting. Deploying an OpenSearch JVM cluster immediately consumes `1.5–2.5 GiB` RAM without first proving whether PostgreSQL 17's native Full-Text Search meets our SLOs.

## 2. Options Considered
- **Option A**: Deploy **OpenSearch** cluster immediately in `M1/M2`.
- **Option B (Chosen)**: **Start with PostgreSQL 17 Denormalized Search Read-Model (`tsvector` + `pg_trgm` + `JSONB` GIN index) behind a clean `ProductSearchRepository` port, and benchmark with `k6` before considering OpenSearch (`Q6`)**.

## 3. Decision (`ACCEPTED`)
1. Define a clean application port `ProductSearchRepository` in `product-service`.
2. Implement `PostgresProductSearchAdapter` in `M2–M4` using a denormalized `product_search_documents` read-model table with:
   - Weighted `tsvector` (`setweight(to_tsvector('simple', name), 'A') || setweight(to_tsvector('simple', description), 'B')`) + `GIN` index.
   - `pg_trgm` trigram GIN index for fuzzy prefix/typo matching.
   - `JSONB` GIN index on `attributes` + B-Tree composite indexes on `(category_path, min_price, is_in_stock)`.
   - Redis Cache-Aside for hot search queries.
3. **Benchmark Gate (`M4 / M7`)**: Run reproducible `k6` search load tests (`50K–250K` SKU catalog dataset) measuring `p50`, `p95`, `p99` latency and `EXPLAIN (ANALYZE, BUFFERS)`. Only introduce an `OpenSearchProductSearchAdapter` if empirical measurements breach `p95 < 100ms` or require advanced linguistic analyzers not supported by PostgreSQL.

## 4. Consequences & Trade-offs
- **Positive**: Saves `1.5–2.5 GiB` RAM across development and initial K8s clusters; demonstrates evidence-driven engineering (`benchmark before adopting heavy infra`).
- **Negative / Cost**: Requires maintaining trigger/event synchronization into `product_search_documents`.

## 5. Rejected Alternatives
- **Option A (Immediate OpenSearch without benchmark evidence)**: Violates our principle of never introducing heavy infrastructure without proving why simpler solutions are insufficient.
