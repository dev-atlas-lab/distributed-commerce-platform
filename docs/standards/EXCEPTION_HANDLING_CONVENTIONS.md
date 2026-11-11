# Cross-Language Exception & Error Handling Conventions

- **Document ID:** `DCP-STD-EXC-001`
- **Status:** `ACCEPTED`
- **Applicability:** All polyglot microservices and shared building blocks (Java, .NET, Python)

---

## 1. Core Principles & Motivation

In a high-throughput, distributed event-driven commerce platform, exception class proliferation (creating a dedicated subclass for every domain invariant or business rule) creates unnecessary code churn, refactoring friction, and packaging bloat.

Instead, the platform enforces a **small, generic, reusable 5-category exception taxonomy** across Java, .NET, and Python. Every expected business, validation, or lookup failure uses a stable, machine-readable **Error Code** (`errorCode`) paired with a descriptive, human-readable message.

### Core Rules
1. **Never create an exception class for a single invariant**: Business rules, validation constraints, and terminal states are represented using the standard generic taxonomy with specific error codes.
2. **Never use exceptions for normal control flow**: Exceptions signal abnormal conditions, invariant violations, or external technical failures.
3. **Never leak infrastructure details**: Database connection strings, SQL queries, Kafka broker topologies, or internal stack traces must never appear in public API error payloads.
4. **Preserve RFC 9457 `ProblemDetails` compliance**: All presentation-layer adapters standardize exceptions into `application/problem+json` containing `errorCode`, `title`, `status`, `detail`, `instance`, `correlationId`, `traceId`, and `timestamp`.

---

## 2. Generic Exception Taxonomy

| Category | Architectural Layer | Responsibility / Failure Kind | Default HTTP Status | RFC 9457 Type URI | Public Message Sanitization |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`DomainException`** | Domain / Application | Business rule or domain invariant violations (e.g. terminal state mutation, invalid state transition). | **`409 Conflict`** (or `422`) | `https://problems.commerce.dev-atlas.lab/domain-violation` | **No** (safe business explanation) |
| **`ValidationException`** | Domain (VOs) / Application | Input constraint violations, value object format constraints (e.g. bad scale, invalid format). | **`400 Bad Request`** | `https://problems.commerce.dev-atlas.lab/validation-error` | **No** (safe validation explanation) |
| **`NotFoundException`** | Application | Requested aggregate or resource was not found by identifier. | **`404 Not Found`** | `https://problems.commerce.dev-atlas.lab/not-found` | **No** (safe lookup explanation) |
| **`ConflictException`** | Application / Domain | State conflict with existing resources (e.g. optimistic concurrency collision, duplicate unique key). | **`409 Conflict`** | `https://problems.commerce.dev-atlas.lab/conflict` | **No** (safe state explanation) |
| **`InfrastructureException`** | Infrastructure | Outbound technical failures (PostgreSQL, Kafka, Redis, external third-party HTTP). | **`500 Internal Server Error`** | `https://problems.commerce.dev-atlas.lab/infrastructure-error` | **Yes** (Client sees: *"An infrastructure error occurred while processing the request."*) |

---

## 3. Error Code Single Source of Truth & Cross-Language Code Generation

To guarantee that any change or addition to an `errorCode` automatically takes effect across all services in Java, .NET, and Python, error codes are defined in a single authoritative catalog:

- **Canonical Specification:** [`docs/error-contracts/error-codes.json`](file:///home/anhltn/projects/distributed-commerce-platform/docs/error-contracts/error-codes.json)
- **Generator Script:** [`scripts/generate-error-codes.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/generate-error-codes.sh)
- **CI Parity Verification:** Run automatically via `./scripts/verify-foundation.sh` (`python3 scripts/generate-error-codes.py --check`).

### Generated Language Artifacts:
- **Java 21:** [`ErrorCode.java`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/error/ErrorCode.java) (`com.devatlas.commerce.common.error.ErrorCode`)
- **.NET 10:** [`ErrorCode.cs`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Exceptions/ErrorCode.cs) (`Commerce.BuildingBlocks.Exceptions.ErrorCode`)
- **Python 3.12+:** [`error_codes.py`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/error_codes.py) (`commerce_common.ErrorCode`)

### Workflow When Modifying Error Codes:
1. Edit or add the error code in `docs/error-contracts/error-codes.json`.
2. Run `./scripts/generate-error-codes.sh`.
3. Java, .NET, and Python building blocks are instantly updated.
4. If an existing error code was renamed or deleted, the compilers and type-checkers (`javac`, `dotnet build`, `mypy --strict`) immediately flag any outdated usages across all services.

### Error Code Conventions:
- **Format:** `UPPER_SNAKE_CASE` (e.g. `PRODUCT_ARCHIVED`, `INVALID_MONEY_AMOUNT`, `CAMPAIGN_EXPIRED`).
- **Stable:** Decoupled from exception class names and human-readable messages. Changing an error message or refactoring code must not change its machine-readable `errorCode`.
- **Domain-Prefixed or Descriptive:** Clear context without redundant words (e.g. `DUPLICATE_SKU_CODE`, `PRODUCT_REQUIRES_ACTIVE_VARIANT`).

---

## 4. Layer Responsibilities

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Presentation / Inbound Adapters (Api)                    │
│    Translates exceptions to RFC 9457 ProblemDetails.        │
│    Injects correlationId, traceId, errorCode, timestamp.    │
└──────────────────────────────┬──────────────────────────────┘
                               │ invokes
┌──────────────────────────────▼──────────────────────────────┐
│ 2. Application Layer                                        │
│    Orchestrates use cases.                                  │
│    Throws NotFoundException on missing aggregate.           │
│    Throws ConflictException on optimistic lock / duplicate.│
└──────────────────────────────┬──────────────────────────────┘
                               │ invokes
┌──────────────────────────────▼──────────────────────────────┐
│ 3. Domain Layer (Pure POCO / POJO)                          │
│    Enforces business rules and invariants.                  │
│    Throws DomainException or ValidationException.          │
│    ZERO framework or presentation dependencies.             │
└──────────────────────────────┬──────────────────────────────┘
                               │ invokes
┌──────────────────────────────▼──────────────────────────────┐
│ 4. Infrastructure Outbound Adapters                         │
│    Wraps external driver errors in InfrastructureException. │
│    Logs raw technical errors, root causes, and SQLSTATE.    │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Cross-Language Implementation Examples

### 5.1 Java 21 (`Spring Boot 3.4`)

```java
// Domain invariant: terminal status
if (this.status == ProductStatus.ARCHIVED) {
    throw new DomainException(ErrorCode.PRODUCT_ARCHIVED, "Archived products cannot be modified.");
}

// Domain value object validation
if (amount.compareTo(BigDecimal.ZERO) <= 0) {
    throw new ValidationException(ErrorCode.INVALID_MONEY_AMOUNT, "Amount must be strictly greater than zero.");
}

// Application use-case lookup
Product product = productRepository.findById(productId)
    .orElseThrow(() -> new NotFoundException(ErrorCode.PRODUCT_NOT_FOUND, "Product " + productId + " not found."));

// Infrastructure adapter wrapping DB/network error
try {
    redisTemplate.opsForValue().set(key, value);
} catch (Exception ex) {
    throw new InfrastructureException(ErrorCode.REDIS_CONNECTION_FAILURE, "Failed to cache product " + key, ex);
}
```

### 5.2 .NET 10 (`C#`)

```csharp
// Domain invariant
if (campaign.IsExpired(now))
{
    throw new DomainException(ErrorCode.CAMPAIGN_EXPIRED, "The flash sale campaign has already ended.");
}

// Validation constraint
if (string.IsNullOrWhiteSpace(couponCode))
{
    throw new ValidationException(ErrorCode.INVALID_COUPON_CODE, "Coupon code cannot be empty.");
}

// Application use-case lookup
var customer = await customerRepository.FindByIdAsync(customerId, ct)
    ?? throw new NotFoundException(ErrorCode.CUSTOMER_NOT_FOUND, $"Customer {customerId} was not found.");

// Infrastructure adapter
try
{
    await dbConnection.ExecuteAsync(command);
}
catch (NpgsqlException ex)
{
    throw new InfrastructureException(ErrorCode.DATABASE_ERROR, "Database command failed.", ex);
}
```

### 5.3 Python 3.12+ (`FastAPI`)

```python
# Domain invariant
if session.is_closed:
    raise DomainException(ErrorCode.SESSION_CLOSED, "Cannot submit messages to a closed session.")

# Validation constraint
if not query.strip():
    raise ValidationException(ErrorCode.EMPTY_QUERY, "Search query must not be blank.")

# Application lookup
session = await session_repo.find_by_id(session_id)
if not session:
    raise NotFoundException(ErrorCode.AGENT_SESSION_NOT_FOUND, f"Session {session_id} does not exist.")

# Infrastructure technical failure
try:
    await pgvector_client.search(embedding)
except Exception as exc:
    raise InfrastructureException(ErrorCode.PGVECTOR_SEARCH_ERROR, "Vector search index query failed.") from exc
```

---

## 6. RFC 9457 `ProblemDetails` Contract Specification

Every API response for client-facing failures has media type `application/problem+json`:

```json
{
  "type": "https://problems.commerce.dev-atlas.lab/domain-violation",
  "title": "Domain Rule Violation",
  "status": 409,
  "detail": "Archived products cannot be modified.",
  "instance": "/api/v1/products/c6001a4f-4d92-4f76-9c44-9ad93e430001",
  "errorCode": "PRODUCT_ARCHIVED",
  "service": "catalog-service",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "traceId": "0af7651916cd43dd8448eb211c80319c",
  "timestamp": "2026-11-11T16:50:00Z"
}
```

---

## 7. Anti-Patterns to Avoid

| Anti-Pattern | Why It Is Prohibited | Correct Pattern |
| :--- | :--- | :--- |
| **One Class Per Invariant** (e.g. `ArchivedProductModificationException`) | Causes subclass explosion, package pollution, and fragile inheritance hierarchies. | Use `DomainException("PRODUCT_ARCHIVED", ...)`. |
| **Generating `errorCode` from Exception Message** | Fragile; changes when wording or translations are modified. | Pass explicit, immutable `errorCode` string constant. |
| **Catching `Exception` Broadly in Domain/App** | Swallows unexpected programmer defects (NPE, assertion failures) and masks bugs. | Only catch specific handled exceptions; let unhandled errors bubble to top-level boundary handler. |
| **Leaking SQL / Secrets in `InfrastructureException`** | Security violation (`OWASP A01/A05`); exposes internal topology to callers. | Log raw exception internally with stack trace; sanitize the response detail string. |
| **Importing Web Frameworks in Domain** | Breaks Clean Architecture / DDD purity. | Domain exceptions are pure POJO/POCO classes with zero web framework imports. |
