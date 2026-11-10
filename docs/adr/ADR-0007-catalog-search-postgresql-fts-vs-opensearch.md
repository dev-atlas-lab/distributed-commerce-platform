# ADR-0007: Phased Product Catalog Search: PostgreSQL 17 FTS + `pg_trgm` before OpenSearch

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
The platform requires fast product catalog search supporting keyword queries, typo tolerance, category hierarchy filtering, price range filtering, attribute facets (e.g., brand, RAM, storage), and sorting. We must evaluate whether to deploy **OpenSearch** immediately or use **PostgreSQL 17 Full-Text Search (`tsvector` + GIN index + `pg_trgm` + JSONB GIN)** first.

## 2. Options Considered
- **Option A**: Deploy **OpenSearch** cluster immediately in `M1/M2`.
- **Option B**: Phased Search Strategy — implement **PostgreSQL 17 Denormalized Search Read-Model (`tsvector` + `pg_trgm` + `JSONB` GIN index)** behind a clean `ProductSearchPort` interface in `M2–M4`, and introduce **OpenSearch** only as an optional `M4/M7` adapter if benchmark evidence shows PG FTS cannot meet `p95 < 100ms` at target catalog scale.

## 3. Decision
Adopt **Option B (Phased Search Strategy)**:
1. Define a clean domain/application port `ProductSearchRepository` in `product-service`.
2. In `M2–M4`, implement `PostgresProductSearchAdapter` using a denormalized `product_search_documents` table equipped with:
   - Weighted `tsvector` (`setweight(to_tsvector('simple', name), 'A') || setweight(to_tsvector('simple', description), 'B')`) + `GIN` index.
   - `pg_trgm` trigram GIN index for fuzzy prefix/typo matching.
   - `JSONB` GIN index on `attributes` (`{"brand": "Apple", "storage": "256GB"}`) + B-Tree composite indexes on `(category_path, min_price, is_in_stock)`.
   - Redis Cache-Aside for top/popular search queries.

## 4. Consequences & Trade-offs
- **Positive**: Saves **`1.5–2.5 GiB` RAM** (OpenSearch JVM heap requirement), eliminates dual-storage synchronization complexity in `M2`, and teaches advanced PostgreSQL indexing (`GIN`, `tsvector`, `pg_trgm`, `EXPLAIN ANALYZE` tuning) capable of handling `100K–1M` products at `<20ms`.
- **Negative / Cost**: Lacks complex BM25 synonym analyzers and multi-node shard scaling out of the box compared to OpenSearch (which can be plugged into `ProductSearchRepository` later if desired).

## 5. Rejected Alternatives
- **Option A (OpenSearch in M1/M2)**: Violates our working philosophy ("Do not introduce technologies without a clear engineering purpose; explain operational cost before adopting"). A single OpenSearch node requires `1–2 GiB` heap alone, which would starve our 9 microservices on a 4–8 GiB VM.
