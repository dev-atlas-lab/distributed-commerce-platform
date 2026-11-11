namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Canonical cross-language error codes.
/// Generated from docs/error-contracts/error-codes.json. Do not edit directly.
/// </summary>
public enum ErrorCode
{
    /// <summary>General invalid request parameter or malformed argument.</summary>
    INVALID_ARGUMENT,
    /// <summary>Money amount must be strictly greater than zero and conform to currency decimal scale.</summary>
    INVALID_MONEY_AMOUNT,
    /// <summary>Domain entity identifier UUID is null or malformed.</summary>
    INVALID_DOMAIN_IDENTIFIER,
    /// <summary>Product name is blank or exceeds allowed length constraints.</summary>
    INVALID_PRODUCT_NAME,
    /// <summary>Product brand is blank or exceeds allowed length constraints.</summary>
    INVALID_PRODUCT_BRAND,
    /// <summary>Slug format is invalid or contains prohibited characters.</summary>
    INVALID_SLUG,
    /// <summary>SKU code format does not match required alphanumeric pattern.</summary>
    INVALID_SKU_CODE,
    /// <summary>Product media list violates primary media or ordering invariants.</summary>
    INVALID_PRODUCT_MEDIA,
    /// <summary>Coupon code format is invalid or malformed.</summary>
    INVALID_COUPON_CODE,
    /// <summary>Search or agent query string is blank or invalid.</summary>
    INVALID_QUERY,
    /// <summary>Search query cannot be empty.</summary>
    EMPTY_QUERY,
    /// <summary>Archived product is terminal and cannot be modified or published.</summary>
    PRODUCT_ARCHIVED,
    /// <summary>An active product must maintain at least one active variant.</summary>
    PRODUCT_REQUIRES_ACTIVE_VARIANT,
    /// <summary>All variants belonging to a product must share the same currency code.</summary>
    INCONSISTENT_VARIANT_CURRENCY,
    /// <summary>SKU code is immutable once a product has been published.</summary>
    IMMUTABLE_SKU_CODE,
    /// <summary>Aggregate version cannot be reconstituted with a version less than 1.</summary>
    INVALID_AGGREGATE_VERSION,
    /// <summary>Flash sale campaign has ended or is no longer active.</summary>
    CAMPAIGN_EXPIRED,
    /// <summary>AI agent token context budget was exceeded.</summary>
    INSUFFICIENT_CONTEXT_BUDGET,
    /// <summary>AI agent session has been closed.</summary>
    SESSION_CLOSED,
    /// <summary>Requested product aggregate does not exist.</summary>
    PRODUCT_NOT_FOUND,
    /// <summary>Requested variant does not exist on the product.</summary>
    PRODUCT_VARIANT_NOT_FOUND,
    /// <summary>Requested campaign does not exist.</summary>
    CAMPAIGN_NOT_FOUND,
    /// <summary>Requested customer does not exist.</summary>
    CUSTOMER_NOT_FOUND,
    /// <summary>Requested AI agent session does not exist.</summary>
    AGENT_SESSION_NOT_FOUND,
    /// <summary>SKU code already exists within the product aggregate.</summary>
    DUPLICATE_SKU_CODE,
    /// <summary>Aggregate version conflict during optimistic concurrency check.</summary>
    CONCURRENCY_CONFLICT,
    /// <summary>A conflicting active session already exists.</summary>
    ACTIVE_SESSION_CONFLICT,
    /// <summary>Database connectivity or execution failure.</summary>
    DATABASE_ERROR,
    /// <summary>Database query timed out.</summary>
    DATABASE_TIMEOUT,
    /// <summary>Failed to establish database connection.</summary>
    DATABASE_CONNECTION_ERROR,
    /// <summary>Redis cache or Lua script execution timed out.</summary>
    REDIS_GATEWAY_TIMEOUT,
    /// <summary>Failed to connect to Redis instance.</summary>
    REDIS_CONNECTION_FAILURE,
    /// <summary>Connection to pgvector store was refused.</summary>
    PGVECTOR_CONNECTION_REFUSED,
    /// <summary>Vector similarity search failed.</summary>
    PGVECTOR_SEARCH_ERROR,
    /// <summary>Unexpected internal server failure.</summary>
    INTERNAL_SERVER_ERROR
}

public static class ErrorCodeExtensions
{
    public static string AsString(this ErrorCode errorCode) => errorCode.ToString();
}
