package com.devatlas.commerce.common.pagination;

import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * Standard offset-based pagination response envelope.
 *
 * @param <T>           item type
 * @param items         items in the current page
 * @param page          current 1-based page index
 * @param size          current page size
 * @param totalElements total number of elements across all pages
 * @param totalPages    total number of pages
 * @param hasNext       whether a subsequent page exists
 * @param hasPrevious   whether an anterior page exists
 */
public record PagedResult<T>(
        List<T> items,
        int page,
        int size,
        long totalElements,
        int totalPages,
        boolean hasNext,
        boolean hasPrevious) {

    public PagedResult {
        items = items != null ? Collections.unmodifiableList(items) : Collections.emptyList();
    }

    public static <T> PagedResult<T> of(List<T> items, int page, int size, long totalElements) {
        int totalPages = size > 0 ? (int) Math.ceil((double) totalElements / size) : 0;
        boolean hasNext = page < totalPages;
        boolean hasPrevious = page > 1;
        return new PagedResult<>(items, page, size, totalElements, totalPages, hasNext, hasPrevious);
    }

    public static <T> PagedResult<T> empty(int page, int size) {
        return new PagedResult<>(Collections.emptyList(), page, size, 0L, 0, false, false);
    }
}
