package com.devatlas.commerce.common.pagination;

import java.util.Objects;

/**
 * Standard cursor-based pagination request model.
 *
 * @param cursor    opaque base64 cursor token (null for first page)
 * @param limit     maximum items to return (1..100)
 * @param direction query direction (FORWARD or BACKWARD)
 */
public record CursorRequest(
        String cursor,
        int limit,
        String direction) {

    public static final int DEFAULT_LIMIT = 20;
    public static final int MAX_LIMIT = 100;
    public static final String FORWARD = "FORWARD";
    public static final String BACKWARD = "BACKWARD";

    public CursorRequest {
        if (limit < 1 || limit > MAX_LIMIT) {
            throw new IllegalArgumentException("limit must be between 1 and " + MAX_LIMIT);
        }
        direction = Objects.requireNonNullElse(direction, FORWARD);
    }

    public static CursorRequest of(String cursor, int limit) {
        return new CursorRequest(cursor, limit, FORWARD);
    }

    public static CursorRequest of(int limit) {
        return new CursorRequest(null, limit, FORWARD);
    }

    public static CursorRequest defaultRequest() {
        return new CursorRequest(null, DEFAULT_LIMIT, FORWARD);
    }
}
