using Commerce.BuildingBlocks.Exceptions;
using Xunit;

namespace Commerce.BuildingBlocks.Tests;

public sealed class ExceptionTaxonomyTests
{
    [Fact]
    public void DomainException_ShouldRetainErrorCodeAndMessage()
    {
        var ex = new DomainException("PRODUCT_ARCHIVED", "Archived products cannot be modified.");
        Assert.Equal("PRODUCT_ARCHIVED", ex.ErrorCode);
        Assert.Equal("Archived products cannot be modified.", ex.Message);
    }

    [Fact]
    public void DomainException_ShouldSupportTypedErrorCode()
    {
        var ex = new DomainException(ErrorCode.PRODUCT_ARCHIVED, "Archived products cannot be modified.");
        Assert.Equal("PRODUCT_ARCHIVED", ex.ErrorCode);
        Assert.Equal("Archived products cannot be modified.", ex.Message);
    }

    [Fact]
    public void DomainException_ShouldThrow_WhenErrorCodeIsNull()
    {
        Assert.Throws<ArgumentNullException>(() => new DomainException(null!, "message"));
    }

    [Fact]
    public void ValidationException_ShouldRetainErrorCodeAndInnerException()
    {
        var inner = new FormatException("invalid number");
        var ex = new ValidationException("INVALID_MONEY_AMOUNT", "Amount must be positive", inner);
        Assert.Equal("INVALID_MONEY_AMOUNT", ex.ErrorCode);
        Assert.Equal("Amount must be positive", ex.Message);
        Assert.Same(inner, ex.InnerException);
    }

    [Fact]
    public void NotFoundException_ShouldRetainErrorCodeAndMessage()
    {
        var ex = new NotFoundException("PRODUCT_NOT_FOUND", "Product not found");
        Assert.Equal("PRODUCT_NOT_FOUND", ex.ErrorCode);
        Assert.Equal("Product not found", ex.Message);
    }

    [Fact]
    public void ConflictException_ShouldRetainErrorCodeAndMessage()
    {
        var ex = new ConflictException("DUPLICATE_SKU_CODE", "SKU code already exists");
        Assert.Equal("DUPLICATE_SKU_CODE", ex.ErrorCode);
        Assert.Equal("SKU code already exists", ex.Message);
    }

    [Fact]
    public void InfrastructureException_ShouldRetainErrorCodeAndInnerException()
    {
        var inner = new TimeoutException("Database connection timed out");
        var ex = new InfrastructureException("DATABASE_TIMEOUT", "DB unreachable", inner);
        Assert.Equal("DATABASE_TIMEOUT", ex.ErrorCode);
        Assert.Same(inner, ex.InnerException);
    }
}
