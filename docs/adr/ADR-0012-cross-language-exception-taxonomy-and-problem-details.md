# ADR-0012: Minimal Cross-Language Exception Taxonomy & Unified RFC 9457 ProblemDetails Architecture

- **Status:** `DESIGN_ACCEPTED`
- **Date:** 2026-11-11
- **Deciders:** Human Architect, Solution Architect Agent, Technical Lead

## 1. Context & Problem
Across the polyglot platform (Java 21, .NET 10, Python 3.12+), error handling risks two extremes:
1. **Specialized Class Proliferation**: Creating an individual exception class for every domain invariant or business rule (e.g. `ArchivedProductModificationException`, `InconsistentVariantCurrencyException`, `ActiveProductRequiresActiveVariantException`), leading to dozens of one-off classes, excessive boilerplate, and package clutter.
2. **Loss of Machine-Readable Semantics**: Using uncharacterized generic exceptions without immutable error codes, making it impossible for API clients to programmatically handle business failures without parsing fragile string messages.

Furthermore, public API responses must consistently adhere to RFC 9457 (`application/problem+json`) with required machine-readable properties (`errorCode`, `traceId`, `correlationId`, `timestamp`, `instance`) while guaranteeing that infrastructure failures (SQL strings, network addresses, credentials) are strictly sanitized.

## 2. Options Considered
- **Option A (Subclass Proliferation)**: Create custom exception subclasses for each domain rule, value object constraint, and entity state transition across every service.
- **Option B (Framework-Heavy Abstraction)**: Introduce complex custom exception interception frameworks with dynamic reflection and localized messages.
- **Option C (Pragmatic Minimal Taxonomy + Stable Error Codes)**: Standardize on a minimal 5-category exception taxonomy (`DomainException`, `ValidationException`, `NotFoundException`, `ConflictException`, `InfrastructureException`) paired with immutable machine-readable error codes and native presentation handlers.

## 3. Decision
We adopt **Option C**:

1. **Standard 5-Category Taxonomy**:
   - `DomainException`: Business rule / domain invariant violations (default HTTP `409 Conflict` or `422`).
   - `ValidationException`: Input constraint and Value Object validation failures (HTTP `400 Bad Request`).
   - `NotFoundException`: Aggregate / entity lookup misses (HTTP `404 Not Found`).
   - `ConflictException`: Resource state conflict, optimistic concurrency collisions, duplicate keys (HTTP `409 Conflict`).
   - `InfrastructureException`: Outbound technical failures from external systems (HTTP `500 Internal Server Error`).

2. **Immutable Machine-Readable Error Codes**:
   - Every domain or application exception requires an explicit, immutable `errorCode` string in `UPPER_SNAKE_CASE` (e.g. `PRODUCT_ARCHIVED`, `INVALID_MONEY_AMOUNT`, `PRODUCT_REQUIRES_ACTIVE_VARIANT`).
   - Error codes are never dynamically generated from exception messages or class names.

3. **RFC 9457 ProblemDetails Compliance**:
   - Java (`GlobalProblemDetailsExceptionHandler`), .NET (`GlobalExceptionHandler : IExceptionHandler`), and Python (`register_problem_details_handlers`) uniformly populate `errorCode`, `correlationId`, `traceId`, `timestamp`, `title`, `status`, and `detail`.
   - Technical failures wrapped in `InfrastructureException` or unhandled errors are strictly sanitized in the client response (`detail: "An infrastructure error occurred while processing the request."`).

4. **Pure Domain Boundary**:
   - Common domain exceptions are framework-agnostic POJOs / POCOs with zero dependencies on Spring, ASP.NET Core, or FastAPI, ensuring Clean Architecture dependency rules are preserved.

## 4. Consequences & Trade-offs
- **Positive**: Eliminates dozens of redundant exception classes; provides a clean, predictable API error response model across all languages; guarantees zero leakage of internal infrastructure details.
- **Negative**: Developers must define descriptive string error codes instead of relying on class name inspection in tests (asserting `ex.getErrorCode()` instead of `isInstanceOf(...)`).

## 5. Rejected Alternatives
- **Option A (Subclass Proliferation)**: Rejected to prevent architectural bloat and fragile inheritance hierarchies.
- **Option B (Framework-Heavy Abstraction)**: Rejected to avoid unnecessary reflection and maintain language-idiomatic simplicity.
