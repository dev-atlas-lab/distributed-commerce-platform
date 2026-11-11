# Cross-Language REST API & Pagination Conventions

- **Document ID:** `DCP-STD-API-001`
- **Status:** `ACCEPTED`
- **Applicability:** All polyglot microservices, gateways, and client SDKs (Java 21, .NET 10, Python 3.12+)

---

## 1. Core REST Architectural Principles

1. **Resource-Oriented URIs**: Nouns in plural kebab-case (e.g. `/api/v1/products`, `/api/v1/flash-sales/{campaignId}/claim`).
2. **HTTP Verb Semantics**:
   - `GET`: Safe, idempotent resource or collection queries.
   - `POST`: State-mutating commands or subordinate resource creation.
   - `PUT`: Complete idempotent resource replacement.
   - `PATCH`: Partial state transition or atomic delta.
   - `DELETE`: Idempotent resource removal or archival.
3. **HTTP Status Code Precision**:
   - `200 OK`: Successful query or synchronous mutation returning a representation.
   - `201 Created`: Resource successfully created (with `Location` header where appropriate).
   - `202 Accepted`: Asynchronous processing initiated (e.g. Flash Sale Redis slot claimed; Saga starting).
   - `204 No Content`: Successful mutation with no response body.
   - `400 Bad Request`: Validation failure or malformed payload.
   - `401 Unauthorized`: Missing or invalid Bearer JWT.
   - `403 Forbidden`: Authenticated identity lacks required scope or role.
   - `404 Not Found`: Target resource does not exist.
   - `409 Conflict`: Business state conflict (invariant violation, terminal state mutation, concurrency mismatch).
   - `429 Too Many Requests`: Rate limit exceeded.
   - `500 Internal Server Error`: Unhandled technical failure (strictly sanitized).

---

## 2. Mandatory HTTP Header Conventions

| Header Name | Direction | Applicable Requests | Purpose |
| :--- | :--- | :--- | :--- |
| `Authorization` | Request | All protected endpoints | Bearer RS256 JWT carrying user `sub`, `roles`, and `jti` (`ADR-0006`). |
| `Idempotency-Key` | Request | All state-mutating `POST` and `PATCH` calls | UUIDv4 string preventing duplicate processing on client retries (`ADR-0003`). |
| `X-Correlation-Id` | Both | All HTTP requests and responses | Unique trace identifier correlating logs, traces, and Kafka outbox events (`ADR-0011`). |
| `traceparent` | Both | All HTTP requests and responses | W3C distributed tracing context header. |

---

## 3. Response Formats

### 3.1 Single Resource Success Responses (Direct DTOs)
Success payloads return the direct domain resource DTO matching the **OpenAPI 3.1** specification.
The platform **prohibits** arbitrary wrapping envelopes such as `{ "success": true, "data": { ... } }` because HTTP status codes, headers, and OpenAPI schemas already provide explicit transport and typing semantics.

```json
{
  "productId": "c6001a4f-4d92-4f76-9c44-9ad93e430001",
  "name": "iPhone 16 Pro",
  "status": "ACTIVE",
  "currency": "USD",
  "basePrice": 999.00,
  "createdAt": "2026-11-11T16:00:00Z"
}
```

### 3.2 Error Responses (RFC 9457 `ProblemDetails`)
All error responses across all services strictly follow RFC 9457 (`application/problem+json`):

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
  "timestamp": "2026-11-11T17:10:00Z"
}
```

---

## 4. Standardized Pagination Architectures

The platform establishes **two distinct pagination models** to match different performance and consistency requirements:

```
                               ┌────────────────────────────────────────┐
                               │  Choose Pagination Model by Use Case   │
                               └───────────────────┬────────────────────┘
                                                   │
                         ┌─────────────────────────┴─────────────────────────┐
                         ▼                                                   ▼
         ┌───────────────────────────────┐                   ┌───────────────────────────────┐
         │ 1. Offset-Based Pagination    │                   │ 2. Cursor-Based Pagination    │
         ├───────────────────────────────┤                   ├───────────────────────────────┤
         │ • Bounded administrative UI   │                   │ • High-volume event streams   │
         │ • Direct page number jumping  │                   │ • Infinite-scrolling feeds    │
         │ • Total count display         │                   │ • Order history & ledgers     │
         │ • O(N) offset query cost      │                   │ • O(1) indexed key lookup     │
         └───────────────────────────────┘                   └───────────────────────────────┘
```

---

## 5. Offset-Based Pagination (`PageRequest` & `PagedResult<T>`)

Used for administrative and back-office tables where the total dataset is bounded and jumping to a specific page number is required.

### 5.1 Request Parameters
| Query Parameter | Type | Required | Default | Allowed Values | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `page` | `integer` | No | `1` | $\ge 1$ | 1-based page index |
| `size` | `integer` | No | `20` | `1..100` | Items per page (enforces max limit = 100) |
| `sortBy` | `string` | No | `null` | Allowlisted fields | Entity field name to sort by |
| `sortDir` | `string` | No | `DESC` | `ASC` \| `DESC` | Sort direction |

*Example Query:*
```http
GET /api/v1/products?page=2&size=20&sortBy=name&sortDir=ASC HTTP/1.1
```

### 5.2 Response Envelope Schema (`PagedResult<T>`)
```json
{
  "items": [
    { "productId": "...", "name": "iPhone 16 Pro" }
  ],
  "page": 2,
  "size": 20,
  "totalElements": 45,
  "totalPages": 3,
  "hasNext": true,
  "hasPrevious": true
}
```

---

## 6. Cursor-Based Pagination (`CursorRequest` & `CursorResult<T>`)

Used for customer-facing mobile feeds, infinite scrolling, audit logs, and ledger feeds (`orders`, `inventory_ledger`). Avoids the severe performance degradation of `OFFSET N` queries and eliminates duplicate or missing rows when new records are inserted while a user is scrolling.

### 6.1 Request Parameters
| Query Parameter | Type | Required | Default | Allowed Values | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `cursor` | `string` | No | `null` | Base64-opaque token | Token encoding sort value + tiebreaker ID |
| `limit` | `integer` | No | `20` | `1..100` | Maximum items to return in slice |
| `direction` | `string` | No | `FORWARD` | `FORWARD` \| `BACKWARD` | Paging traversal direction |

*Example Query:*
```http
GET /api/v1/orders?cursor=ZXlKaGJHY2lPaUpTVXp...&limit=25 HTTP/1.1
```

### 6.2 Response Envelope Schema (`CursorResult<T>`)
```json
{
  "items": [
    { "orderId": "019316a8-7c4b-7000-8a12-3f9c8d7e6b5a", "orderNumber": "ORD-2026-0001" }
  ],
  "nextCursor": "ZXlKaGJHY2lPaUpTVXp...",
  "prevCursor": null,
  "hasMore": true
}
```

---

## 7. Polyglot Building Block Reference

Shared building blocks provide type-safe, validated pagination records across all languages:

### 7.1 Java 21 (`commerce-building-blocks`)
- Package: `com.devatlas.commerce.common.pagination`
- Types: [`PageRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/pagination/PageRequest.java), [`PagedResult<T>`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/pagination/PagedResult.java), [`CursorRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/pagination/CursorRequest.java), [`CursorResult<T>`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/pagination/CursorResult.java), [`SortDirection`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/java/src/main/java/com/devatlas/commerce/common/pagination/SortDirection.java)

```java
PageRequest pageReq = PageRequest.of(1, 20, "createdAt", SortDirection.DESC);
PagedResult<ProductDto> result = PagedResult.of(productList, pageReq.page(), pageReq.size(), totalCount);
```

### 7.2 .NET 10 (`Commerce.BuildingBlocks`)
- Namespace: `Commerce.BuildingBlocks.Pagination`
- Types: [`PageRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Pagination/PageRequest.cs), [`PagedResult<T>`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Pagination/PagedResult.cs), [`CursorRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Pagination/CursorRequest.cs), [`CursorResult<T>`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Pagination/CursorResult.cs), [`SortDirection`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/dotnet/Commerce.BuildingBlocks/Pagination/SortDirection.cs)

```csharp
var pageReq = new PageRequest(Page: 1, Size: 20, SortBy: "createdAt", SortDir: SortDirection.Desc);
var result = PagedResult<PromotionDto>.Of(promotions, pageReq.Page, pageReq.Size, totalCount);
```

### 7.3 Python 3.12+ (`commerce-common`)
- Module: `commerce_common.pagination`
- Types: [`PageRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/pagination.py), [`PagedResult[T]`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/pagination.py), [`CursorRequest`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/pagination.py), [`CursorResult[T]`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/pagination.py), [`SortDirection`](file:///home/anhltn/projects/distributed-commerce-platform/src/building-blocks/python/src/commerce_common/pagination.py)

```python
page_req = PageRequest(page=1, size=20, sort_by="created_at", sort_dir=SortDirection.DESC)
result = PagedResult[SessionDto].create(items=sessions, page=page_req.page, size=page_req.size, total_elements=total_count)
```

---

## 8. Anti-Patterns to Avoid

| Prohibited Anti-Pattern | Reason | Required Standard |
| :--- | :--- | :--- |
| **Unbounded `size` or `limit` parameter** | Allowing clients to pass `size=100000` leads to thread starvation and DB Out-Of-Memory. | Strictly enforce `size <= 100` and `limit <= 100` via validation. |
| **0-Based Page Indexes in Public API** | Confusing for API consumers and frontend developers. | Public API `page` is strictly 1-based; adapters calculate internal DB `offset = (page - 1) * size`. |
| **Offset Pagination on Large Real-Time Feeds** | `OFFSET 100000` scans and discards 100,000 DB rows, causing massive CPU/IO spikes and pagination skips. | Use cursor-based pagination with indexed `(created_at, id)` seek queries. |
| **Leaking Raw SQL or Unhashed IDs in Cursor** | Exposes physical database schema details. | Encode cursor values as opaque base64 tokens. |
