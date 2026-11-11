# ADR-0008: Multi-Provider AI Abstraction, `pgvector` Physical Index Limits (`vector` vs. `halfvec`) & Generation Isolation

- **Status:** `ACCEPTED` (`Q7` Multi-Provider AI Abstraction & Zero-Privilege Boundary Accepted in `M0.1`; `CH-06` `pgvector` Physical Index Ceiling & Generation Isolation Corrections `PROPOSED` in `M0.2.1`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We are building `ai-agent-service` (`Python 3.12+`, `FastAPI`) with provider abstraction (`OpenAI`, `Google Gemini`, `Anthropic` — `Q7`).
To engineer the `pgvector` RAG store (`ai_agent_db`) accurately (`CH-06`), we must account for two fundamental constraints:
1. **Equal dimensions never imply equivalent vector spaces**: Comparing a `768d` Gemini vector against a `768d` OpenAI vector produces meaningless cosine distances across orthogonal latent spaces.
2. **Physical `pgvector` ANN Index Limits (PostgreSQL 8 KB Page Limit)**:
   - While an unindexed `vector` or `halfvec` column can store up to **`16,000` dimensions**, **HNSW and IVFFlat ANN indexes support at most `2,000` dimensions for 32-bit float `vector` (`vector_cosine_ops`)** and up to **`4,000` dimensions for 16-bit float `halfvec` (`halfvec_cosine_ops`)**!
   - Therefore, a `3072`-dimensional embedding (`OpenAI text-embedding-3-large`) **cannot** use a normal `vector` HNSW/IVFFlat index and must either be indexed as **`halfvec(3072)` (`halfvec_cosine_ops`)** or use Matryoshka dimension reduction (`dimensions <= 2000`).

## 2. Options Considered
- **Option A**: Single fixed `vector(768)` column shared across providers.
- **Option B**: Unbounded `vector` assuming `3072` dimensions can use standard `vector_cosine_ops` HNSW (`M0.2` draft).
- **Option C**: **Multi-Provider Port Abstraction + Generation-Isolated `embedding_index_generations` & `chunk_embeddings` Schema Enforcing `VECTOR_FP32 (<= 2000d)` vs. `HALFVEC_FP16 (<= 4000d)` ANN Index Ceilings (`CH-06`) + Blue/Green Atomic Re-Indexing**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `ChatCompletionProviderPort` and `EmbeddingProviderPort` abstract **OpenAI**, **Google Gemini**, and **Anthropic**.
   - `ai-agent-service` connects ONLY to `ai_agent_db`, never to business databases, Redis, or Kafka, and binds caller identity strictly from the verified JWT (`sub`).
2. **Refined `M0.2.1` `pgvector` Storage, Indexing & Migration Architecture (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-06`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Database-Enforced ANN Index Ceiling (`INV-EMB-02`)**: `embedding_index_generations` enforces `CHECK ((index_storage_type = 'VECTOR_FP32' AND dimensions <= 2000) OR (index_storage_type = 'HALFVEC_FP16' AND dimensions <= 4000))`.
   - **Half-Precision (`halfvec`) Indexing & Benchmark Targets**: `chunk_embeddings` stores vectors and builds per-generation partial functional HNSW indexes (`USING hnsw ((embedding::halfvec(D)) halfvec_cosine_ops) WHERE generation_id = '...'`), supporting `384`, `768`, `1024`, `1536`, and `3072` dimensions natively with `50%` tuple storage reduction (`2` bytes/dim vs `4` bytes/dim). Recall (`Recall@10 >= 0.95`) and latency (`p95 < 50ms`) are tracked as empirical benchmark targets (`NEEDS_EVIDENCE`) to be measured on our actual catalog in `M5/M7`, never assumed as universal guarantees.
   - **Strict Model-Generation Isolation (`INV-EMB-01`)**: Every RAG similarity query filters `WHERE generation_id = :activeGenId` and encodes the user query with the exact `(provider, model_name, model_version, dimensions)` of that active generation.
   - **Zero-Downtime Blue/Green Migration (`INV-EMB-03`)**: New generations are populated and HNSW-indexed in `BUILDING` state while live traffic reads the `ACTIVE` generation, flipping atomically once `100%` indexed.

## 4. Consequences & Trade-offs
- **Positive**: Respects real PostgreSQL `pgvector` HNSW/IVFFlat page-size limits (`2000d` for `vector`, `4000d` for `halfvec`); supports `3072d` models via `halfvec_cosine_ops` without index creation failures; cuts vector tuple storage in half.
- **Negative / Cost**: FP16 (`halfvec`) has 10 mantissa bits vs. FP32's 23 mantissa bits (requiring empirical `Recall@10` verification in `M5`, with optional FP32 `vector_cosine_ops` available for any generation $\le 2000$ dimensions).

## 5. Rejected Alternatives
- **Option B (Assuming `vector(3072)` works with standard `vector_cosine_ops` HNSW)**: Fails in PostgreSQL `pgvector` with `ERROR: column cannot have more than 2000 dimensions for hnsw index`.
