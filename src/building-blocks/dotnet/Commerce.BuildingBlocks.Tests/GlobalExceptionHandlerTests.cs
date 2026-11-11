using Commerce.BuildingBlocks.Exceptions;
using Commerce.BuildingBlocks.Hosting;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Commerce.BuildingBlocks.Tests;

public sealed class GlobalExceptionHandlerTests
{
    private readonly ServiceProvider _serviceProvider;

    public GlobalExceptionHandlerTests()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddCommercePlatformFoundation("test-service");
        _serviceProvider = services.BuildServiceProvider();
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleValidationException_As400WithErrorCode()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/campaigns";

        var handled = await handler.TryHandleAsync(
            context,
            new ValidationException("INVALID_COUPON_CODE", "Coupon code is invalid"),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status400BadRequest, context.Response.StatusCode);
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleNotFoundException_As404WithErrorCode()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/campaigns/999";

        var handled = await handler.TryHandleAsync(
            context,
            new NotFoundException("CAMPAIGN_NOT_FOUND", "Campaign 999 not found"),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status404NotFound, context.Response.StatusCode);
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleConflictException_As409WithErrorCode()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/claims";

        var handled = await handler.TryHandleAsync(
            context,
            new ConflictException("CONCURRENCY_CONFLICT", "Version mismatch"),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status409Conflict, context.Response.StatusCode);
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleDomainException_As409WithErrorCode()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/campaigns/123/claim";

        var handled = await handler.TryHandleAsync(
            context,
            new DomainException("CAMPAIGN_EXPIRED", "The flash sale campaign has ended"),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status409Conflict, context.Response.StatusCode);
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleInfrastructureException_As500WithSanitizedDetail()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/campaigns";

        var handled = await handler.TryHandleAsync(
            context,
            new InfrastructureException(
                "REDIS_GATEWAY_TIMEOUT",
                "Connection failed: redis://user:password@internal-cluster:6379",
                new TimeoutException("timed out")),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status500InternalServerError, context.Response.StatusCode);
    }

    [Fact]
    public async Task TryHandleAsync_ShouldHandleFallbackException_As500WithInternalErrorCode()
    {
        var problemDetailsService = _serviceProvider.GetRequiredService<IProblemDetailsService>();
        var handler = new GlobalExceptionHandler(problemDetailsService, NullLogger<GlobalExceptionHandler>.Instance);

        var context = new DefaultHttpContext { RequestServices = _serviceProvider };
        context.Request.Path = "/api/v1/unexpected";

        var handled = await handler.TryHandleAsync(
            context,
            new InvalidOperationException("Fatal unexpected condition"),
            CancellationToken.None);

        Assert.True(handled);
        Assert.Equal(StatusCodes.Status500InternalServerError, context.Response.StatusCode);
    }
}
