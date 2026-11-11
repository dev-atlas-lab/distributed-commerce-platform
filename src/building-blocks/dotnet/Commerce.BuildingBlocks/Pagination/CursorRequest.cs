namespace Commerce.BuildingBlocks.Pagination;

/// <summary>
/// Standard cursor-based pagination request model.
/// </summary>
/// <param name="Cursor">Opaque base64 cursor token (null for first page)</param>
/// <param name="Limit">Maximum items to return (1..100)</param>
/// <param name="Direction">Query direction (FORWARD or BACKWARD)</param>
public sealed record CursorRequest
{
    public const int DefaultLimit = 20;
    public const int MaxLimit = 100;
    public const string Forward = "FORWARD";
    public const string Backward = "BACKWARD";

    public string? Cursor { get; init; }
    public int Limit { get; init; }
    public string Direction { get; init; }

    public CursorRequest(string? cursor = null, int limit = DefaultLimit, string direction = Forward)
    {
        if (limit is < 1 or > MaxLimit)
        {
            throw new ArgumentOutOfRangeException(nameof(limit), $"Limit must be between 1 and {MaxLimit}.");
        }

        Cursor = cursor;
        Limit = limit;
        Direction = string.IsNullOrWhiteSpace(direction) ? Forward : direction;
    }
}
