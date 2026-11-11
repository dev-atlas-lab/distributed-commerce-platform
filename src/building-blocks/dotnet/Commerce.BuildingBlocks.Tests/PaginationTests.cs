using Commerce.BuildingBlocks.Pagination;
using Xunit;

namespace Commerce.BuildingBlocks.Tests;

public sealed class PaginationTests
{
    [Fact]
    public void PageRequest_ShouldComputeOffsetAndDefaults()
    {
        var req = new PageRequest(3, 25, "name", SortDirection.Asc);
        Assert.Equal(3, req.Page);
        Assert.Equal(25, req.Size);
        Assert.Equal("name", req.SortBy);
        Assert.Equal(SortDirection.Asc, req.SortDir);
        Assert.Equal(50L, req.Offset);
    }

    [Fact]
    public void PageRequest_ShouldThrow_WhenOutOfRange()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new PageRequest(0, 20));
        Assert.Throws<ArgumentOutOfRangeException>(() => new PageRequest(1, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new PageRequest(1, 101));
    }

    [Fact]
    public void PagedResult_ShouldComputeNavigationProperties()
    {
        var items = new[] { "item1", "item2" };
        var result = PagedResult<string>.Of(items, 2, 10, 25);

        Assert.Equal(items, result.Items);
        Assert.Equal(2, result.Page);
        Assert.Equal(10, result.Size);
        Assert.Equal(25L, result.TotalElements);
        Assert.Equal(3, result.TotalPages);
        Assert.True(result.HasNext);
        Assert.True(result.HasPrevious);
    }

    [Fact]
    public void PagedResult_Empty_ShouldHaveZeroPages()
    {
        var empty = PagedResult<string>.Empty();
        Assert.Empty(empty.Items);
        Assert.Equal(0L, empty.TotalElements);
        Assert.Equal(0, empty.TotalPages);
        Assert.False(empty.HasNext);
        Assert.False(empty.HasPrevious);
    }

    [Fact]
    public void CursorRequest_ShouldSupportDefaultsAndValidation()
    {
        var req = new CursorRequest("cursor-token", 15);
        Assert.Equal("cursor-token", req.Cursor);
        Assert.Equal(15, req.Limit);
        Assert.Equal(CursorRequest.Forward, req.Direction);

        Assert.Throws<ArgumentOutOfRangeException>(() => new CursorRequest(limit: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new CursorRequest(limit: 101));
    }

    [Fact]
    public void CursorResult_ShouldSupportSlices()
    {
        var items = new[] { 10, 20 };
        var result = CursorResult<int>.Of(items, "next-cur", true);

        Assert.Equal(items, result.Items);
        Assert.Equal("next-cur", result.NextCursor);
        Assert.Null(result.PrevCursor);
        Assert.True(result.HasMore);

        var empty = CursorResult<int>.Empty();
        Assert.Empty(empty.Items);
        Assert.False(empty.HasMore);
    }
}
