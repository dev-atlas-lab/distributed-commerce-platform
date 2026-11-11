"""Tests for standard pagination models (PageRequest, PagedResult, CursorRequest, CursorResult)."""

from __future__ import annotations

import pytest
from commerce_common import (
    CursorRequest,
    CursorResult,
    PagedResult,
    PageRequest,
    SortDirection,
)
from pydantic import ValidationError


def test_page_request_defaults_and_offset() -> None:
    req = PageRequest(page=3, size=25, sort_by="created_at", sort_dir=SortDirection.ASC)
    assert req.page == 3
    assert req.size == 25
    assert req.sort_by == "created_at"
    assert req.sort_dir == SortDirection.ASC
    assert req.offset == 50


def test_page_request_validation() -> None:
    with pytest.raises(ValidationError):
        PageRequest(page=0, size=20)

    with pytest.raises(ValidationError):
        PageRequest(page=1, size=0)

    with pytest.raises(ValidationError):
        PageRequest(page=1, size=101)


def test_paged_result_calculation() -> None:
    items = ["item-1", "item-2"]
    result = PagedResult[str].create(items=items, page=2, size=10, total_elements=25)
    assert result.items == ["item-1", "item-2"]
    assert result.page == 2
    assert result.size == 10
    assert result.total_elements == 25
    assert result.total_pages == 3
    assert result.has_next is True
    assert result.has_previous is True


def test_paged_result_empty_and_terminal() -> None:
    empty = PagedResult[str].empty()
    assert empty.items == []
    assert empty.total_elements == 0
    assert empty.total_pages == 0
    assert empty.has_next is False
    assert empty.has_previous is False

    last_page = PagedResult[str].create(items=["last"], page=3, size=10, total_elements=25)
    assert last_page.has_next is False
    assert last_page.has_previous is True


def test_cursor_request_defaults_and_validation() -> None:
    req = CursorRequest(cursor="token_xyz", limit=15)
    assert req.cursor == "token_xyz"
    assert req.limit == 15
    assert req.direction == "FORWARD"

    with pytest.raises(ValidationError):
        CursorRequest(limit=0)

    with pytest.raises(ValidationError):
        CursorRequest(limit=101)


def test_cursor_result_slices() -> None:
    items = [{"id": 1}, {"id": 2}]
    result = CursorResult[dict[str, int]].create(items=items, next_cursor="next_abc", has_more=True)
    assert result.items == items
    assert result.next_cursor == "next_abc"
    assert result.prev_cursor is None
    assert result.has_more is True

    empty = CursorResult[dict[str, int]].empty()
    assert empty.items == []
    assert empty.has_more is False
