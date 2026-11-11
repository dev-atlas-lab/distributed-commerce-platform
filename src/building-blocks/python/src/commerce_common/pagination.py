"""Standard pagination request and response models for Commerce platform (Python 3.12+)."""

from __future__ import annotations

import math
from enum import StrEnum

from pydantic import BaseModel, Field


class SortDirection(StrEnum):
    """Sorting direction for paginated queries."""

    ASC = "ASC"
    DESC = "DESC"


class PageRequest(BaseModel):
    """Standard offset-based pagination request model."""

    page: int = Field(default=1, ge=1, description="1-based page index")
    size: int = Field(default=20, ge=1, le=100, description="Items per page (1..100)")
    sort_by: str | None = Field(default=None, description="Optional field name to sort by")
    sort_dir: SortDirection = Field(default=SortDirection.DESC, description="Sort direction")

    @property
    def offset(self) -> int:
        """Computes the 0-based database row offset."""
        return (self.page - 1) * self.size


class PagedResult[T](BaseModel):
    """Standard offset-based pagination response envelope."""

    items: list[T]
    page: int
    size: int
    total_elements: int
    total_pages: int
    has_next: bool
    has_previous: bool

    @classmethod
    def create(cls, items: list[T], page: int, size: int, total_elements: int) -> PagedResult[T]:
        """Constructs a PagedResult computing total_pages, has_next, and has_previous."""
        total_pages = math.ceil(total_elements / size) if size > 0 else 0
        has_next = page < total_pages
        has_previous = page > 1
        return cls(
            items=items,
            page=page,
            size=size,
            total_elements=total_elements,
            total_pages=total_pages,
            has_next=has_next,
            has_previous=has_previous,
        )

    @classmethod
    def empty(cls, page: int = 1, size: int = 20) -> PagedResult[T]:
        """Constructs an empty PagedResult."""
        return cls(
            items=[],
            page=page,
            size=size,
            total_elements=0,
            total_pages=0,
            has_next=False,
            has_previous=False,
        )


class CursorRequest(BaseModel):
    """Standard cursor-based pagination request model."""

    cursor: str | None = Field(default=None, description="Opaque cursor token (null for first page)")
    limit: int = Field(default=20, ge=1, le=100, description="Maximum items to return (1..100)")
    direction: str = Field(default="FORWARD", description="Paging direction (FORWARD or BACKWARD)")


class CursorResult[T](BaseModel):
    """Standard cursor-based pagination response envelope."""

    items: list[T]
    next_cursor: str | None = None
    prev_cursor: str | None = None
    has_more: bool

    @classmethod
    def create(
        cls,
        items: list[T],
        next_cursor: str | None,
        has_more: bool,
        prev_cursor: str | None = None,
    ) -> CursorResult[T]:
        """Constructs a CursorResult slice."""
        return cls(
            items=items,
            next_cursor=next_cursor,
            prev_cursor=prev_cursor,
            has_more=has_more,
        )

    @classmethod
    def empty(cls) -> CursorResult[T]:
        """Constructs an empty CursorResult slice."""
        return cls(items=[], next_cursor=None, prev_cursor=None, has_more=False)
