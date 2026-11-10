# ADR-0008: Multi-Provider AI Abstraction (`OpenAI` / `Gemini` / `Anthropic`), Zero-Privilege Boundary & `pgvector` RAG

- **Status:** `ACCEPTED` (Approved in M0.1 — Q7 Multi-Provider LLM Abstraction + Zero-Privilege Tool Boundary)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We are building `ai-agent-service` (`Python 3.12+`, `FastAPI`) for Customer Shopping and Admin Operations Assistants.
1. Hardcoding a single LLM vendor SDK (`openai` only or `google-genai` only) locks the platform to one provider's pricing, rate limits, and availability (`Q7`).
2. Giving AI agents direct SQL access (`Text-to-SQL`) or trusting LLM-generated user IDs in tool calls creates severe Prompt Injection and IDOR vulnerabilities.

## 2. Options Considered
- **Option A**: Hardcode a single vendor SDK + direct read-only DB access.
- **Option B (Chosen)**: **Multi-Provider LLM & Embedding Abstraction Port (`OpenAI`, `Google Gemini`, `Anthropic` + Local OpenAI-Compatible) + Zero-Privilege API-Only Tool Boundary + `pgvector` in isolated `ai_agent_db`**.

## 3. Decision (`ACCEPTED`)
1. **Multi-Provider AI Abstraction (`Q7 — ACCEPTED`)**:
   - Define strict protocol/port interfaces in `services/python/ai-agent-service/app/domain/ports/llm_port.py`:
     - `ChatCompletionProviderPort` (supporting structured output, streaming SSE deltas, and normalized tool-calling schemas across **OpenAI**, **Google Gemini**, and **Anthropic Claude**).
     - `EmbeddingProviderPort` (normalizing embedding generation with configurable vector dimensions, e.g., `768` or `1536`, via Matryoshka/output-dimension parameters where supported so `ai_agent_db` `vector(768)` or `vector(1536)` remains consistent across providers).
   - Select active provider dynamically via configuration (`AI_PROVIDER=openai | gemini | anthropic`) with automatic fallback/circuit-breaker support.
2. **Strict Network & Credential Isolation**:
   - `ai-agent-service` connects ONLY to `ai_agent_db` (PostgreSQL 17 + `pgvector`). It holds zero credentials to any business database, Redis cache, or Kafka producer.
3. **JWT-Bound Tool Execution**:
   - The Python tool executor binds caller identity strictly from the verified HTTP `Authorization: Bearer <jwt>` in request `contextvars`—never accepting `customer_id` from LLM tool arguments.
4. **Human-in-the-Loop (HITL) Gate**:
   - Any administrative state-mutating action creates a `PendingHumanApproval` record requiring an explicit signed HTTP confirmation from an authenticated `ADMIN_OPS` user.

## 4. Consequences & Trade-offs
- **Positive**: Vendor-agnostic switching between OpenAI, Gemini, and Anthropic without touching agent business workflows or tool definitions; mathematical prevention of cross-tenant IDOR at the tool layer.
- **Negative / Cost**: Requires maintaining normalized tool-call and token-usage adapter mappers for each of the 3 providers.

## 5. Rejected Alternatives
- **Option A (Single hardcoded vendor / direct DB access)**: Creates vendor lock-in and violates Mandatory Rule #9.
