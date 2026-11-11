package com.devatlas.commerce.common.pagination;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.Test;

class PaginationTest {

    @Test
    void shouldCreateValidPageRequestAndComputeOffset() {
        PageRequest req = PageRequest.of(3, 20, "createdAt", SortDirection.ASC);
        assertThat(req.page()).isEqualTo(3);
        assertThat(req.size()).isEqualTo(20);
        assertThat(req.sortBy()).isEqualTo("createdAt");
        assertThat(req.sortDirection()).isEqualTo(SortDirection.ASC);
        assertThat(req.offset()).isEqualTo(40L);
    }

    @Test
    void shouldRejectInvalidPageOrSizeInPageRequest() {
        assertThatThrownBy(() -> PageRequest.of(0, 20))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("page must be greater than or equal to 1");

        assertThatThrownBy(() -> PageRequest.of(1, 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("size must be between 1 and 100");

        assertThatThrownBy(() -> PageRequest.of(1, 101))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("size must be between 1 and 100");
    }

    @Test
    void shouldComputePagedResultNavigationProperties() {
        List<String> items = List.of("item1", "item2");
        PagedResult<String> result = PagedResult.of(items, 2, 10, 25L);

        assertThat(result.items()).containsExactly("item1", "item2");
        assertThat(result.page()).isEqualTo(2);
        assertThat(result.size()).isEqualTo(10);
        assertThat(result.totalElements()).isEqualTo(25L);
        assertThat(result.totalPages()).isEqualTo(3);
        assertThat(result.hasNext()).isTrue();
        assertThat(result.hasPrevious()).isTrue();
    }

    @Test
    void shouldHandleEmptyAndTerminalPagedResult() {
        PagedResult<String> empty = PagedResult.empty(1, 20);
        assertThat(empty.items()).isEmpty();
        assertThat(empty.totalElements()).isEqualTo(0L);
        assertThat(empty.totalPages()).isEqualTo(0);
        assertThat(empty.hasNext()).isFalse();
        assertThat(empty.hasPrevious()).isFalse();

        PagedResult<String> lastPage = PagedResult.of(List.of("last"), 3, 10, 25L);
        assertThat(lastPage.hasNext()).isFalse();
        assertThat(lastPage.hasPrevious()).isTrue();
    }

    @Test
    void shouldCreateCursorRequestWithDefaultsAndValidation() {
        CursorRequest req = CursorRequest.of("token-123", 25);
        assertThat(req.cursor()).isEqualTo("token-123");
        assertThat(req.limit()).isEqualTo(25);
        assertThat(req.direction()).isEqualTo(CursorRequest.FORWARD);

        assertThatThrownBy(() -> CursorRequest.of(0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("limit must be between 1 and 100");

        assertThatThrownBy(() -> CursorRequest.of(150))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("limit must be between 1 and 100");
    }

    @Test
    void shouldCreateCursorResultWithSlices() {
        List<Integer> numbers = List.of(1, 2, 3);
        CursorResult<Integer> result = CursorResult.of(numbers, "next-token-xyz", true);

        assertThat(result.items()).containsExactly(1, 2, 3);
        assertThat(result.nextCursor()).isEqualTo("next-token-xyz");
        assertThat(result.prevCursor()).isNull();
        assertThat(result.hasMore()).isTrue();

        CursorResult<Integer> empty = CursorResult.empty();
        assertThat(empty.items()).isEmpty();
        assertThat(empty.hasMore()).isFalse();
    }
}
