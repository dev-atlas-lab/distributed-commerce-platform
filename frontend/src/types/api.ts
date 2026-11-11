/**
 * RFC 9457 Problem Details schema matching backend GlobalProblemDetailsExceptionHandler
 * and docs/api-contracts/order-and-flashsale.v1.openapi.yaml
 */
export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail: string;
  instance?: string;
  errorCode: string;
  traceId?: string;
  correlationId?: string;
  timestamp: string;
  invalidParams?: Array<{
    name: string;
    reason: string;
  }>;
}

/**
 * Standard Offset Pagination Request & Response contracts
 * matching docs/standards/API_CONVENTIONS.md
 */
export interface PageRequest {
  page?: number;
  size?: number;
  sortBy?: string;
  sortDirection?: "ASC" | "DESC";
}

export interface PagedResult<T> {
  items: T[];
  page: number;
  size: number;
  totalElements: number;
  totalPages: number;
  hasNext: boolean;
  hasPrevious: boolean;
}

/**
 * Standard Cursor-based Pagination Request & Response contracts
 * matching docs/standards/API_CONVENTIONS.md
 */
export interface CursorRequest {
  limit?: number;
  cursor?: string | null;
  sortDirection?: "ASC" | "DESC";
}

export interface CursorResult<T> {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
  limit: number;
}
