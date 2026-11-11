using System.Diagnostics;
using Commerce.BuildingBlocks.Chaos;
using Commerce.BuildingBlocks.Observability;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Commerce.BuildingBlocks.Hosting;

/// <summary>
/// Registers shared platform building blocks: RFC 9457 ProblemDetails, Correlation ID propagation,
/// health/readiness probes (<c>NFR-OPS-001</c>), and the <c>CH-07</c> fail-closed startup guard.
/// </summary>
public static class PlatformServiceExtensions
{
    public static IServiceCollection AddCommercePlatformFoundation(
        this IServiceCollection services,
        string serviceName)
    {
        services.AddProblemDetails(options =>
        {
            options.CustomizeProblemDetails = context =>
            {
                context.ProblemDetails.Extensions["service"] = serviceName;
                context.ProblemDetails.Extensions["timestamp"] = DateTimeOffset.UtcNow.ToString("O");
                if (context.HttpContext.Items.TryGetValue(CorrelationIdMiddleware.CorrelationIdItemKey, out var correlationId)
                    && correlationId is string corrStr)
                {
                    context.ProblemDetails.Extensions["correlationId"] = corrStr;
                }

                var traceId = Activity.Current?.TraceId.ToString() ?? context.HttpContext.TraceIdentifier;
                context.ProblemDetails.Extensions["traceId"] = traceId;
            };
        });

        services.AddHealthChecks()
            .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live", "ready"]);

        services.AddHostedService<FaultInjectionStartupGuard>();

        services.AddExceptionHandler<GlobalExceptionHandler>();

        return services;
    }

    public static WebApplication UseCommercePlatformFoundation(this WebApplication app)
    {
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseExceptionHandler();
        app.UseStatusCodePages();

        app.MapHealthChecks("/health/live", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("live")
        });

        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("ready")
        });

        return app;
    }
}
