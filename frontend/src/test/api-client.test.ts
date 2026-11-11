import { describe, it, expect, vi, beforeEach } from "vitest";
import { api, ApiClientError } from "../lib/api-client";
import type { ProblemDetails } from "../types/api";

describe("apiClient", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("should inject X-Correlation-Id and Idempotency-Key on mutating requests", async () => {
    const mockResponse = { id: "order-123", status: "PENDING" };

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => mockResponse,
    } as Response);

    const result = await api.post("/orders", { skuId: "sku-001", quantity: 2 });

    expect(result).toEqual(mockResponse);
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    const [calledUrl, calledConfig] = fetchSpy.mock.calls[0] as [string, RequestInit];
    expect(calledUrl).toContain("/api/v1/orders");
    expect(calledConfig.method).toBe("POST");

    const headers = calledConfig.headers as Record<string, string>;
    expect(headers["Content-Type"]).toBe("application/json");
    expect(headers["X-Correlation-Id"]).toBeDefined();
    expect(headers["Idempotency-Key"]).toBeDefined();
  });

  it("should parse RFC 9457 ProblemDetails on HTTP 409 conflict and throw ApiClientError", async () => {
    const problemPayload: ProblemDetails = {
      type: "https://problems.commerce.dev-atlas.lab/insufficient-stock",
      title: "Insufficient Stock",
      status: 409,
      detail: "Requested quantity exceeds available inventory stock.",
      errorCode: "INSUFFICIENT_STOCK",
      traceId: "trace-abc-123",
      timestamp: "2026-11-11T12:00:00Z",
    };

    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: false,
      status: 409,
      statusText: "Conflict",
      json: async () => problemPayload,
    } as Response);

    await expect(api.post("/orders", {})).rejects.toThrow(ApiClientError);

    try {
      await api.post("/orders", {});
    } catch (err) {
      if (err instanceof ApiClientError) {
        expect(err.status).toBe(409);
        expect(err.errorCode).toBe("INSUFFICIENT_STOCK");
        expect(err.traceId).toBe("trace-abc-123");
        expect(err.message).toBe("Requested quantity exceeds available inventory stock.");
      }
    }
  });

  it("should properly format query parameters for pagedGet", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ items: [], page: 2, size: 20, totalElements: 0, totalPages: 0, hasNext: false, hasPrevious: true }),
    } as Response);

    await api.pagedGet("/products", {
      page: 2,
      size: 20,
      sortBy: "price",
      sortDirection: "DESC",
    });

    const [calledUrl] = fetchSpy.mock.calls[0] as [string, RequestInit];
    expect(calledUrl).toContain("page=2");
    expect(calledUrl).toContain("size=20");
    expect(calledUrl).toContain("sortBy=price");
    expect(calledUrl).toContain("sortDirection=DESC");
  });
});
