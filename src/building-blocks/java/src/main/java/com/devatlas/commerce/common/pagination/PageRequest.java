package com.devatlas.commerce.common.pagination;

import java.util.Objects;

/**
 * Standard offset-based pagination request model.
 *
 * @param page          1-based page index (minimum 1)
 * @param size          page size (1..100)
 * @param sortBy        optional sort field
 * @param sortDirection sort direction (ASC or DESC)
 */
public record PageRequest(
        int page,
        int size,
        String sortBy,
        SortDirection sortDirection) {

    public static final int DEFAULT_PAGE = 1;
    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 100;

    public PageRequest {
        if (page < 1) {
            throw new IllegalArgumentException("page must be greater than or equal to 1");
        }
        if (size < 1 || size > MAX_SIZE) {
            throw new IllegalArgumentException("size must be between 1 and " + MAX_SIZE);
        }
        sortDirection = Objects.requireNonNullElse(sortDirection, SortDirection.DESC);
    }

    public static PageRequest of(int page, int size) {
        return new PageRequest(page, size, null, SortDirection.DESC);
    }

    public static PageRequest of(int page, int size, String sortBy, SortDirection sortDirection) {
        return new PageRequest(page, size, sortBy, sortDirection);
    }

    public static PageRequest defaultPage() {
        return new PageRequest(DEFAULT_PAGE, DEFAULT_SIZE, null, SortDirection.DESC);
    }

    public long offset() {
        return (long) (page - 1) * size;
    }
}
