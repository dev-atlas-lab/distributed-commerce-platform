package com.devatlas.commerce.common.error;

/**
 * Canonical cross-language error codes.
 * Generated from docs/error-contracts/error-codes.json. Do not edit directly.
 */
public enum ErrorCode {
    /** General invalid request parameter or malformed argument. */
    INVALID_ARGUMENT("INVALID_ARGUMENT"),
    /**
     * Money amount must be strictly greater than zero and conform to currency
     * decimal scale.
     */
    INVALID_MONEY_AMOUNT("INVALID_MONEY_AMOUNT"),
    /** Domain entity identifier UUID is null or malformed. */
    INVALID_DOMAIN_IDENTIFIER("INVALID_DOMAIN_IDENTIFIER"),
    /** Product name is blank or exceeds allowed length constraints. */
    INVALID_PRODUCT_NAME("INVALID_PRODUCT_NAME"),
    /** Product brand is blank or exceeds allowed length constraints. */
    INVALID_PRODUCT_BRAND("INVALID_PRODUCT_BRAND"),
    /** Slug format is invalid or contains prohibited characters. */
    INVALID_SLUG("INVALID_SLUG"),
    /** SKU code format does not match required alphanumeric pattern. */
    INVALID_SKU_CODE("INVALID_SKU_CODE"),
    /** Product media list violates primary media or ordering invariants. */
    INVALID_PRODUCT_MEDIA("INVALID_PRODUCT_MEDIA"),
    /** Coupon code format is invalid or malformed. */
    INVALID_COUPON_CODE("INVALID_COUPON_CODE"),
    /** Search or agent query string is blank or invalid. */
    INVALID_QUERY("INVALID_QUERY"),
    /** Attributes map is null, empty, or contains invalid keys/values. */
    INVALID_ATTRIBUTES("INVALID_ATTRIBUTES"),
    /** Search query cannot be empty. */
    EMPTY_QUERY("EMPTY_QUERY"),
    /** Archived product is terminal and cannot be modified or published. */
    PRODUCT_ARCHIVED("PRODUCT_ARCHIVED"),
    /** An active product must maintain at least one active variant. */
    PRODUCT_REQUIRES_ACTIVE_VARIANT("PRODUCT_REQUIRES_ACTIVE_VARIANT"),
    /** All variants belonging to a product must share the same currency code. */
    INCONSISTENT_VARIANT_CURRENCY("INCONSISTENT_VARIANT_CURRENCY"),
    /** SKU code is immutable once a product has been published. */
    IMMUTABLE_SKU_CODE("IMMUTABLE_SKU_CODE"),
    /** Aggregate version cannot be reconstituted with a version less than 1. */
    INVALID_AGGREGATE_VERSION("INVALID_AGGREGATE_VERSION"),
    /** Flash sale campaign has ended or is no longer active. */
    CAMPAIGN_EXPIRED("CAMPAIGN_EXPIRED"),
    /** AI agent token context budget was exceeded. */
    INSUFFICIENT_CONTEXT_BUDGET("INSUFFICIENT_CONTEXT_BUDGET"),
    /** AI agent session has been closed. */
    SESSION_CLOSED("SESSION_CLOSED"),
    /** Requested product aggregate does not exist. */
    PRODUCT_NOT_FOUND("PRODUCT_NOT_FOUND"),
    /** Requested variant does not exist on the product. */
    PRODUCT_VARIANT_NOT_FOUND("PRODUCT_VARIANT_NOT_FOUND"),
    /** Requested campaign does not exist. */
    CAMPAIGN_NOT_FOUND("CAMPAIGN_NOT_FOUND"),
    /** Requested customer does not exist. */
    CUSTOMER_NOT_FOUND("CUSTOMER_NOT_FOUND"),
    /** Requested AI agent session does not exist. */
    AGENT_SESSION_NOT_FOUND("AGENT_SESSION_NOT_FOUND"),
    /** SKU code already exists within the product aggregate. */
    DUPLICATE_SKU_CODE("DUPLICATE_SKU_CODE"),
    /** Aggregate version conflict during optimistic concurrency check. */
    CONCURRENCY_CONFLICT("CONCURRENCY_CONFLICT"),
    /** A conflicting active session already exists. */
    ACTIVE_SESSION_CONFLICT("ACTIVE_SESSION_CONFLICT"),
    /** Database connectivity or execution failure. */
    DATABASE_ERROR("DATABASE_ERROR"),
    /** Database query timed out. */
    DATABASE_TIMEOUT("DATABASE_TIMEOUT"),
    /** Failed to establish database connection. */
    DATABASE_CONNECTION_ERROR("DATABASE_CONNECTION_ERROR"),
    /** Redis cache or Lua script execution timed out. */
    REDIS_GATEWAY_TIMEOUT("REDIS_GATEWAY_TIMEOUT"),
    /** Failed to connect to Redis instance. */
    REDIS_CONNECTION_FAILURE("REDIS_CONNECTION_FAILURE"),
    /** Connection to pgvector store was refused. */
    PGVECTOR_CONNECTION_REFUSED("PGVECTOR_CONNECTION_REFUSED"),
    /** Vector similarity search failed. */
    PGVECTOR_SEARCH_ERROR("PGVECTOR_SEARCH_ERROR"),
    /** Unexpected internal server failure. */
    INTERNAL_SERVER_ERROR("INTERNAL_SERVER_ERROR");

    private final String code;

    ErrorCode(String code) {
        this.code = code;
    }

    public String code() {
        return code;
    }
}
