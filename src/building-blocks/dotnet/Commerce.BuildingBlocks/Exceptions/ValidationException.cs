namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Generic exception representing invalid input data or violated validation constraints.
/// </summary>
public class ValidationException : Exception
{
    public string ErrorCode { get; }

    public ValidationException(ErrorCode errorCode, string message) : this(errorCode.AsString(), message)
    {
    }

    public ValidationException(ErrorCode errorCode, string message, Exception? innerException)
        : this(errorCode.AsString(), message, innerException)
    {
    }

    public ValidationException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }

    public ValidationException(string errorCode, string message, Exception? innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }
}
