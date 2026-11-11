namespace Commerce.BuildingBlocks.Pagination;

/// <summary>
/// Standard offset-based pagination response envelope.
/// </summary>
/// <typeparam name="T">Item type</typeparam>
/// <param name="Items">Items in the current page</param>
/// <param name="Page">Current 1-based page index</param>
/// <param name="Size">Current page size</param>
/// <param name="TotalElements">Total number of elements across all pages</param>
/// <param name="TotalPages">Total number of pages</param>
/// <param name="HasNext">Whether a subsequent page exists</param>
/// <param name="HasPrevious">Whether an anterior page exists</param>
public sealed record PagedResult<T>(
    IReadOnlyList<T> Items,
    int Page,
    int Size,
    long TotalElements,
    int TotalPages,
    bool HasNext,
    bool HasPrevious)
{
    public static PagedResult<T> Of(IReadOnlyList<T> items, int page, int size, long totalElements)
    {
        var totalPages = size > 0 ? (int)Math.Ceiling((double)totalElements / size) : 0;
        var hasNext = page < totalPages;
        var hasPrevious = page > 1;
        return new PagedResult<T>(items, page, size, totalElements, totalPages, hasNext, hasPrevious);
    }

    public static PagedResult<T> Empty(int page = PageRequest.DefaultPage, int size = PageRequest.DefaultSize)
    {
        return new PagedResult<T>([], page, size, 0L, 0, false, false);
    }
}
