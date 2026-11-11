using Commerce.BuildingBlocks.Exceptions;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace Commerce.BuildingBlocks.Hosting;

/// <summary>
/// Standardizes unhandled exceptions into RFC 9457 ProblemDetails responses (<c>NFR-OBS-002</c>).
/// </summary>
public sealed class GlobalExceptionHandler(
    IProblemDetailsService problemDetailsService,
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    private const string DefaultInfrastructureDetail =
        "An infrastructure error occurred while processing the request.";
    private const string DefaultUnhandledDetail =
        "An unexpected internal error occurred.";

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        var (statusCode, title, type, detail, errorCode) = exception switch
        {
            ValidationException valEx => (
                StatusCodes.Status400BadRequest,
                "Bad Request",
                "https://problems.commerce.dev-atlas.lab/validation-error",
                valEx.Message,
                valEx.ErrorCode),
            NotFoundException notFoundEx => (
                StatusCodes.Status404NotFound,
                "Not Found",
                "https://problems.commerce.dev-atlas.lab/not-found",
                notFoundEx.Message,
                notFoundEx.ErrorCode),
            ConflictException conflictEx => (
                StatusCodes.Status409Conflict,
                "Conflict",
                "https://problems.commerce.dev-atlas.lab/conflict",
                conflictEx.Message,
                conflictEx.ErrorCode),
            DomainException domainEx => (
                StatusCodes.Status409Conflict,
                "Domain Rule Violation",
                "https://problems.commerce.dev-atlas.lab/domain-violation",
                domainEx.Message,
                domainEx.ErrorCode),
            InfrastructureException infraEx => (
                StatusCodes.Status500InternalServerError,
                "Internal Technical Failure",
                "https://problems.commerce.dev-atlas.lab/infrastructure-error",
                DefaultInfrastructureDetail,
                infraEx.ErrorCode),
            ArgumentException argEx => (
                StatusCodes.Status400BadRequest,
                "Bad Request",
                "https://problems.commerce.dev-atlas.lab/bad-request",
                argEx.Message,
                "INVALID_ARGUMENT"),
            _ => (
                StatusCodes.Status500InternalServerError,
                "Internal Server Error",
                "https://problems.commerce.dev-atlas.lab/internal-error",
                DefaultUnhandledDetail,
                "INTERNAL_SERVER_ERROR")
        };

        if (statusCode >= StatusCodes.Status500InternalServerError)
        {
            logger.LogError(exception, "Unhandled server error [{ErrorCode}]: {Message}", errorCode, exception.Message);
        }
        else
        {
            logger.LogWarning("Request error [{ErrorCode}]: {Message}", errorCode, exception.Message);
        }

        httpContext.Response.StatusCode = statusCode;

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails =
            {
                Status = statusCode,
                Title = title,
                Type = type,
                Detail = detail,
                Instance = httpContext.Request.Path,
                Extensions =
                {
                    ["errorCode"] = errorCode
                }
            },
            Exception = exception
        });
    }
}
