using Commerce.BuildingBlocks.Chaos;
using Commerce.BuildingBlocks.Observability;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Commerce.BuildingBlocks.Tests;

public sealed class PlatformFoundationTests
{
    [Fact]
    public void FaultInjectionGuard_ShouldThrow_WhenEnabledInProduction()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ENVIRONMENT"] = "production",
                ["FAULT_INJECTION_ENABLED"] = "true"
            })
            .Build();

        var ex = Assert.Throws<InvalidOperationException>(() =>
            FaultInjectionStartupGuard.VerifyConfiguration(configuration, "Production"));

        Assert.Contains("SECURITY_VIOLATION", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void FaultInjectionGuard_ShouldSucceed_WhenDisabledInProduction()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ENVIRONMENT"] = "production",
                ["FAULT_INJECTION_ENABLED"] = "false"
            })
            .Build();

        var ex = Record.Exception(() =>
            FaultInjectionStartupGuard.VerifyConfiguration(configuration, "Production"));

        Assert.Null(ex);
    }

    [Fact]
    public void FaultInjectionGuard_ShouldSucceed_WhenEnabledInChaosEnvironment()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ENVIRONMENT"] = "chaos",
                ["FAULT_INJECTION_ENABLED"] = "true"
            })
            .Build();

        var ex = Record.Exception(() =>
            FaultInjectionStartupGuard.VerifyConfiguration(configuration, "Development"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CorrelationIdMiddleware_ShouldGenerateOrPreserveCorrelationId()
    {
        var middleware = new CorrelationIdMiddleware(
            _ => Task.CompletedTask,
            NullLogger<CorrelationIdMiddleware>.Instance);

        var contextWithoutHeader = new DefaultHttpContext();
        await middleware.InvokeAsync(contextWithoutHeader);
        Assert.False(string.IsNullOrWhiteSpace(
            contextWithoutHeader.Response.Headers[CorrelationIdMiddleware.CorrelationIdHeader]));

        var contextWithHeader = new DefaultHttpContext();
        contextWithHeader.Request.Headers[CorrelationIdMiddleware.CorrelationIdHeader] = "dotnet-corr-001";
        await middleware.InvokeAsync(contextWithHeader);
        Assert.Equal(
            "dotnet-corr-001",
            contextWithHeader.Response.Headers[CorrelationIdMiddleware.CorrelationIdHeader].ToString());
    }
}
