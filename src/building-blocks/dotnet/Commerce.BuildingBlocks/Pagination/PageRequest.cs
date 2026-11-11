namespace Commerce.BuildingBlocks.Pagination;

/// <summary>
/// Standard offset-based pagination request model.
/// </summary>
/// <param name="Page">1-based page index (minimum 1)</param>
/// <param name="Size">Page size (1..100)</param>
/// <param name="SortBy">Optional sort field</param>
/// <param name="SortDir">Sort direction (Asc or Desc)</param>
public sealed record PageRequest
{
    public const int DefaultPage = 1;
    public const int DefaultSize = 20;
    public const int MaxSize = 100;

    public int Page { get; init; }
    public int Size { get; init; }
    public string? SortBy { get; init; }
    public SortDirection SortDir { get; init; }

    public PageRequest(int page = DefaultPage, int size = DefaultSize, string? sortBy = null, SortDirection sortDir = SortDirection.Desc)
    {
        if (page < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(page), "Page must be greater than or equal to 1.");
        }
        if (size is < 1 or > MaxSize)
        {
            throw new ArgumentOutOfRangeException(nameof(size), $"Size must be between 1 and {MaxSize}.");
        }

        Page = page;
        Size = size;
        SortBy = sortBy;
        SortDir = sortDir;
    }

    public long Offset => (long)(Page - 1) * Size;
}
