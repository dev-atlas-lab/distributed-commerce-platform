namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Generic exception representing state conflicts such as version mismatch or duplicate constraints.
/// </summary>
public class ConflictException : Exception
{
    public string ErrorCode { get; }

    public ConflictException(ErrorCode errorCode, string message) : this(errorCode.AsString(), message)
    {
    }

    public ConflictException(ErrorCode errorCode, string message, Exception? innerException)
        : this(errorCode.AsString(), message, innerException)
    {
    }

    public ConflictException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }

    public ConflictException(string errorCode, string message, Exception? innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }
}
