# ADR-0008: Multi-Provider AI Abstraction, Generation-Isolated `pgvector` RAG & Zero-Privilege Boundary

- **Status:** `ACCEPTED` (`Q7` Multi-Provider AI Abstraction & Zero-Privilege Boundary Accepted in `M0.1`; `CH-06` Generation-Isolated Multi-Dimension Embedding Schema `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We are building `ai-agent-service` (`Python 3.12+`, `FastAPI`) with provider abstraction (`OpenAI`, `Google Gemini`, `Anthropic` — `Q7`).
In `M0.1`, we initially suggested forcing all providers into a fixed `vector(768)` column. In `M0.2`, we remove that flawed assumption because:
1. Different models have different native dimensions (`768`, `1024`, `1536`, `3072`).
2. **Equal dimensions do NOT imply compatible vector spaces**: comparing a `768d` Gemini query vector against `768d` OpenAI document vectors computes meaningless cosine distances across orthogonal latent spaces.

## 2. Options Considered
- **Option A**: Single fixed `vector(768)` column shared across providers (`M0.1` draft).
- **Option B**: **Multi-Provider Port Abstraction + Generation-Isolated `embedding_index_generations` & `chunk_embeddings` Schema (`CH-06`) + Blue/Green Atomic Re-Indexing + Zero-Privilege JWT-Bound Tool Calling**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `ChatCompletionProviderPort` and `EmbeddingProviderPort` abstract **OpenAI**, **Google Gemini**, and **Anthropic**.
   - `ai-agent-service` connects ONLY to `ai_agent_db` (`PostgreSQL 17 + pgvector`), never to business databases, Redis, or Kafka, and binds customer identity strictly from the caller's verified JWT (`sub`).
2. **Refined Embedding Storage & Migration Architecture (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-06`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - Separate canonical text (`knowledge_chunks` with `content_hash`) from model-specific vectors (`chunk_embeddings` linked to `embedding_index_generations`).
   - Record `(provider, model_name, model_version, dimensions, distance_metric, status)` on every `embedding_index_generations` row.
   - Enforce **Vector Space Homogeneity (`INV-EMB-01`)**: RAG retrieval always embeds the user query using the exact `(provider, model_name, model_version, dimensions)` of the single `ACTIVE` generation and filters `WHERE generation_id = :activeGenId`.
   - Support **Zero-Downtime Blue/Green Model Migration (`INV-EMB-02`)**: Build new model embeddings in `BUILDING` state while live traffic reads the current `ACTIVE` generation, then flip `ACTIVE` atomically once `100%` indexed.

## 4. Consequences & Trade-offs
- **Positive**: Supports `384`, `768`, `1024`, `1536`, and `3072` dimensions natively; mathematically prevents cross-model vector space contamination; zero RAG downtime during model upgrades.
- **Negative / Cost**: Requires a PK `JOIN` between `chunk_embeddings` and `knowledge_chunks` on top-$K$ retrieved chunks (`<1ms` overhead).

## 5. Rejected Alternatives
- **Option A (Shared `vector(768)` column across models)**: Rejected in `M0.2` because equal dimensionality never implies shared semantic coordinates across different models.
