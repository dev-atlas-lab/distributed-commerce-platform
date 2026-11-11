using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace Commerce.BuildingBlocks.Observability;

/// <summary>
/// Propagates or generates <c>X-Correlation-Id</c> across HTTP requests and binds it to the structured logging scope (<c>NFR-OBS-001</c>).
/// </summary>
public sealed class CorrelationIdMiddleware
{
    public const string CorrelationIdHeader = "X-Correlation-Id";
    public const string CorrelationIdItemKey = "commerce.correlation_id";

    private readonly RequestDelegate _next;
    private readonly ILogger<CorrelationIdMiddleware> _logger;

    public CorrelationIdMiddleware(RequestDelegate next, ILogger<CorrelationIdMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(correlationId))
        {
            correlationId = Guid.NewGuid().ToString();
        }

        context.Items[CorrelationIdItemKey] = correlationId;
        context.Response.Headers[CorrelationIdHeader] = correlationId;

        using (_logger.BeginScope(new Dictionary<string, object>
        {
            ["correlation_id"] = correlationId
        }))
        {
            await _next(context);
        }
    }
}
