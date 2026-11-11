package com.devatlas.commerce.common.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class DomainExceptionTest {

    @Test
    void shouldCreateDomainExceptionWithImmutableErrorCode() {
        DomainException ex = new DomainException("PRODUCT_ARCHIVED", "Archived products cannot be modified.");
        assertThat(ex.getErrorCode()).isEqualTo("PRODUCT_ARCHIVED");
        assertThat(ex.getMessage()).isEqualTo("Archived products cannot be modified.");
    }

    @Test
    void shouldCreateDomainExceptionWithTypedErrorCode() {
        DomainException ex = new DomainException(ErrorCode.PRODUCT_ARCHIVED, "Archived products cannot be modified.");
        assertThat(ex.getErrorCode()).isEqualTo("PRODUCT_ARCHIVED");
        assertThat(ex.getMessage()).isEqualTo("Archived products cannot be modified.");
    }

    @Test
    void shouldRejectNullErrorCodeInDomainException() {
        assertThatThrownBy(() -> new DomainException((String) null, "some error"))
                .isInstanceOf(NullPointerException.class)
                .hasMessageContaining("errorCode must not be null");

        assertThatThrownBy(() -> new DomainException((ErrorCode) null, "some error"))
                .isInstanceOf(NullPointerException.class)
                .hasMessageContaining("errorCode must not be null");
    }

    @Test
    void shouldCreateValidationExceptionWithErrorCodeAndCause() {
        IllegalArgumentException cause = new IllegalArgumentException("invalid value");
        ValidationException ex = new ValidationException("INVALID_MONEY_AMOUNT", "Amount must be positive", cause);
        assertThat(ex.getErrorCode()).isEqualTo("INVALID_MONEY_AMOUNT");
        assertThat(ex.getMessage()).isEqualTo("Amount must be positive");
        assertThat(ex.getCause()).isSameAs(cause);
    }

    @Test
    void shouldCreateNotFoundExceptionWithErrorCode() {
        NotFoundException ex = new NotFoundException("PRODUCT_NOT_FOUND", "Product not found");
        assertThat(ex.getErrorCode()).isEqualTo("PRODUCT_NOT_FOUND");
        assertThat(ex.getMessage()).isEqualTo("Product not found");
    }

    @Test
    void shouldCreateConflictExceptionWithErrorCode() {
        ConflictException ex = new ConflictException("DUPLICATE_SKU_CODE", "SKU code already exists");
        assertThat(ex.getErrorCode()).isEqualTo("DUPLICATE_SKU_CODE");
        assertThat(ex.getMessage()).isEqualTo("SKU code already exists");
    }

    @Test
    void shouldCreateInfrastructureExceptionWithErrorCode() {
        RuntimeException cause = new RuntimeException("DB down");
        InfrastructureException ex = new InfrastructureException("DATABASE_CONNECTION_ERROR", "DB failure", cause);
        assertThat(ex.getErrorCode()).isEqualTo("DATABASE_CONNECTION_ERROR");
        assertThat(ex.getCause()).isSameAs(cause);
    }
}
