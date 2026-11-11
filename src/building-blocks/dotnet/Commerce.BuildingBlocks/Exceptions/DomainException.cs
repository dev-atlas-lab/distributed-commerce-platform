namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Generic exception representing business rule or domain invariant violations.
/// </summary>
public class DomainException : Exception
{
    public string ErrorCode { get; }

    public DomainException(ErrorCode errorCode, string message) : this(errorCode.AsString(), message)
    {
    }

    public DomainException(ErrorCode errorCode, string message, Exception? innerException)
        : this(errorCode.AsString(), message, innerException)
    {
    }

    public DomainException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }

    public DomainException(string errorCode, string message, Exception? innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }
}
