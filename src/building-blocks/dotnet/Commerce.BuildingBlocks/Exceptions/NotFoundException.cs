namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Generic exception representing resource or aggregate lookup failures.
/// </summary>
public class NotFoundException : Exception
{
    public string ErrorCode { get; }

    public NotFoundException(ErrorCode errorCode, string message) : this(errorCode.AsString(), message)
    {
    }

    public NotFoundException(ErrorCode errorCode, string message, Exception? innerException)
        : this(errorCode.AsString(), message, innerException)
    {
    }

    public NotFoundException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }

    public NotFoundException(string errorCode, string message, Exception? innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }
}
