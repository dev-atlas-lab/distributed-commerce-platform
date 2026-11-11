package com.devatlas.commerce.common.pagination;

import java.util.Collections;
import java.util.List;

/**
 * Standard cursor-based pagination response envelope.
 *
 * @param <T>        item type
 * @param items      items in the current slice
 * @param nextCursor opaque cursor to fetch subsequent slice, or null if end reached
 * @param prevCursor optional opaque cursor to fetch previous slice
 * @param hasMore    whether more items exist in the forward direction
 */
public record CursorResult<T>(
        List<T> items,
        String nextCursor,
        String prevCursor,
        boolean hasMore) {

    public CursorResult {
        items = items != null ? Collections.unmodifiableList(items) : Collections.emptyList();
    }

    public static <T> CursorResult<T> of(List<T> items, String nextCursor, boolean hasMore) {
        return new CursorResult<>(items, nextCursor, null, hasMore);
    }

    public static <T> CursorResult<T> of(List<T> items, String nextCursor, String prevCursor, boolean hasMore) {
        return new CursorResult<>(items, nextCursor, prevCursor, hasMore);
    }

    public static <T> CursorResult<T> empty() {
        return new CursorResult<>(Collections.emptyList(), null, null, false);
    }
}
