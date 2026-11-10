# ADR-0001: Polyglot Microservices Topology & Pragmatic Internal Architecture

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We need to design a distributed commerce & flash sale platform that teaches production-grade microservices across **Java 21 (`Spring Boot 3.x`)**, **.NET 10 (`ASP.NET Core`)**, **Python 3.12+ (`FastAPI`)**, and **React (`TypeScript`)**, without creating either an unmaintainable nano-service explosion or a rigid one-size-fits-all internal code structure.

## 2. Options Considered
- **Option A: 15+ Fine-Grained Nano-Services** (separate Cart, Price, Media, Search, Auth, User, Coupon, FlashSale, Inventory, Order, Payment, Refund, Email, SMS, AI services).
- **Option B: 9 Bounded-Context Microservices with Pragmatic Per-Service Internal Architecture** (`api-gateway`, `product-service`, `customer-service`, `order-service`, `inventory-service`, `payment-service`, `promotion-service`, `notification-service`, `ai-agent-service`).
- **Option C: Single-Language Modular Monolith**.

## 3. Decision
Adopt **Option B**:
1. Deploy **9 cohesive services** aligned with DDD Bounded Contexts:
   - **Java 21 (`Spring Boot 3.x`)**: `product-service`, `order-service`, `inventory-service`, `payment-service` (transactional core, Saga orchestration, and stock ledger).
   - **.NET 10 (`ASP.NET Core`)**: `api-gateway` (`YARP`), `customer-service` (auth, profile, cart), `promotion-service` (coupons & Flash Sale Redis Lua gate), `notification-service` (async worker).
   - **Python 3.12+ (`FastAPI`)**: `ai-agent-service` (Shopping & Ops AI Assistants).
2. Apply internal architecture pragmatically:
   - **Clean / Hexagonal Architecture** (`domain`, `application`, `infrastructure`, `presentation`) for domain-rich services (`order`, `inventory`, `payment`, `promotion`, `product`).
   - **Vertical Slice / Lightweight Layered Architecture** for routing/data-centric services (`api-gateway`, `customer`, `notification`).

## 4. Consequences & Trade-offs
- **Positive**: Clear domain ownership, realistic polyglot communication over HTTP/REST and Kafka, and independent horizontal scaling of `promotion-service` and `api-gateway` during Flash Sale spikes.
- **Negative / Cost**: Running 9 services simultaneously requires container memory discipline (`~3–4 GiB` across runtimes), mitigated via Docker Compose profiles (`ADR-0002`) and JVM/.NET heap caps.

## 5. Rejected Alternatives
- **Option A (Nano-services)**: Rejected because splitting Cart from Customer or FlashSale from Promotion introduces chatty synchronous network hops and doubles operational memory overhead without adding architectural learning value.
- **Option C (Modular Monolith)**: Rejected because it does not fulfill the primary mission goals of practicing polyglot microservices (`Java` + `.NET` + `Python`), distributed failure isolation, and multi-VM Kubernetes networking.
