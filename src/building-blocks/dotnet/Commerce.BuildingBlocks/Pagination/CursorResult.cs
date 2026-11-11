namespace Commerce.BuildingBlocks.Pagination;

/// <summary>
/// Standard cursor-based pagination response envelope.
/// </summary>
/// <typeparam name="T">Item type</typeparam>
/// <param name="Items">Items in the current slice</param>
/// <param name="NextCursor">Opaque cursor to fetch subsequent slice, or null if end reached</param>
/// <param name="PrevCursor">Optional opaque cursor to fetch previous slice</param>
/// <param name="HasMore">Whether more items exist in the forward direction</param>
public sealed record CursorResult<T>(
    IReadOnlyList<T> Items,
    string? NextCursor,
    string? PrevCursor,
    bool HasMore)
{
    public static CursorResult<T> Of(IReadOnlyList<T> items, string? nextCursor, bool hasMore)
    {
        return new CursorResult<T>(items, nextCursor, null, hasMore);
    }

    public static CursorResult<T> Of(IReadOnlyList<T> items, string? nextCursor, string? prevCursor, bool hasMore)
    {
        return new CursorResult<T>(items, nextCursor, prevCursor, hasMore);
    }

    public static CursorResult<T> Empty()
    {
        return new CursorResult<T>([], null, null, false);
    }
}
