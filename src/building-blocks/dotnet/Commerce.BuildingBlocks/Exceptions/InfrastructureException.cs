namespace Commerce.BuildingBlocks.Exceptions;

/// <summary>
/// Generic exception representing technical failures from external dependencies or infrastructure.
/// </summary>
public class InfrastructureException : Exception
{
    public string ErrorCode { get; }

    public InfrastructureException(ErrorCode errorCode, string message) : this(errorCode.AsString(), message)
    {
    }

    public InfrastructureException(ErrorCode errorCode, string message, Exception? innerException)
        : this(errorCode.AsString(), message, innerException)
    {
    }

    public InfrastructureException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }

    public InfrastructureException(string errorCode, string message, Exception? innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode ?? throw new ArgumentNullException(nameof(errorCode));
    }
}
