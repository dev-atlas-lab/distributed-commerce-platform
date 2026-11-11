using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Commerce.BuildingBlocks.Chaos;

/// <summary>
/// Enforces <c>CH-07</c> / <c>NFR-SEC-004</c>: Fail-closed startup guard that aborts process startup
/// if fault injection is enabled in a production environment.
/// </summary>
public sealed class FaultInjectionStartupGuard : IHostedService
{
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;
    private readonly ILogger<FaultInjectionStartupGuard> _logger;

    public FaultInjectionStartupGuard(
        IConfiguration configuration,
        IHostEnvironment environment,
        ILogger<FaultInjectionStartupGuard> logger)
    {
        _configuration = configuration;
        _environment = environment;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        VerifyConfiguration(_configuration, _environment.EnvironmentName, _logger);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    public static void VerifyConfiguration(
        IConfiguration configuration,
        string hostEnvironmentName,
        ILogger? logger = null)
    {
        var faultInjectionEnabled =
            bool.TryParse(configuration["FAULT_INJECTION_ENABLED"], out var envFlag) && envFlag
            || bool.TryParse(configuration["Commerce:FaultInjection:Enabled"], out var cfgFlag) && cfgFlag;

        var productionLock =
            bool.TryParse(configuration["PRODUCTION_LOCK"], out var lockFlag) && lockFlag;

        var configuredEnv = (configuration["ENVIRONMENT"] ?? hostEnvironmentName ?? "Development")
            .Trim()
            .ToLowerInvariant();

        var isProdHostEnv = string.Equals(hostEnvironmentName, Environments.Production, StringComparison.OrdinalIgnoreCase);
        var isProduction = productionLock
            || isProdHostEnv
            || configuredEnv is "prod" or "production";

        if (isProduction && faultInjectionEnabled)
        {
            logger?.LogCritical("SECURITY_VIOLATION: Fault injection cannot be enabled when running in production (CH-07).");
            throw new InvalidOperationException(
                "SECURITY_VIOLATION: FAULT_INJECTION_ENABLED=true is forbidden in production environment (CH-07).");
        }
    }
}
