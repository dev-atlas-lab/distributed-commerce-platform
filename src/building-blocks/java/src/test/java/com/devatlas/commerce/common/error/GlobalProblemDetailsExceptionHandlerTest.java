package com.devatlas.commerce.common.error;

import static org.assertj.core.api.Assertions.assertThat;

import com.devatlas.commerce.common.observability.CorrelationIdFilter;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.mock.web.MockHttpServletRequest;

class GlobalProblemDetailsExceptionHandlerTest {

    private final GlobalProblemDetailsExceptionHandler handler = new GlobalProblemDetailsExceptionHandler();
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        request = new MockHttpServletRequest("GET", "/api/v1/products/123");
        MDC.put(CorrelationIdFilter.CORRELATION_ID_MDC_KEY, "test-corr-id-001");
        MDC.put("traceId", "test-trace-id-999");
    }

    @AfterEach
    void tearDown() {
        MDC.clear();
    }

    @Test
    void shouldMapValidationExceptionTo400WithErrorCode() {
        ValidationException ex = new ValidationException("INVALID_MONEY_AMOUNT", "Amount must be greater than zero");

        ProblemDetail problem = handler.handleValidationException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(problem.getTitle()).isEqualTo("Bad Request");
        assertThat(problem.getDetail()).isEqualTo("Amount must be greater than zero");
        assertThat(problem.getType().toString()).isEqualTo("https://problems.commerce.dev-atlas.lab/validation-error");
        assertThat(problem.getProperties()).containsEntry("errorCode", "INVALID_MONEY_AMOUNT");
        assertThat(problem.getProperties()).containsEntry("correlationId", "test-corr-id-001");
        assertThat(problem.getProperties()).containsEntry("traceId", "test-trace-id-999");
        assertThat(problem.getProperties()).containsKey("timestamp");
        assertThat(problem.getInstance().toString()).isEqualTo("/api/v1/products/123");
    }

    @Test
    void shouldMapNotFoundExceptionTo404WithErrorCode() {
        NotFoundException ex = new NotFoundException("PRODUCT_NOT_FOUND", "Product 123 was not found");

        ProblemDetail problem = handler.handleNotFoundException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
        assertThat(problem.getTitle()).isEqualTo("Not Found");
        assertThat(problem.getDetail()).isEqualTo("Product 123 was not found");
        assertThat(problem.getType().toString()).isEqualTo("https://problems.commerce.dev-atlas.lab/not-found");
        assertThat(problem.getProperties()).containsEntry("errorCode", "PRODUCT_NOT_FOUND");
    }

    @Test
    void shouldMapConflictExceptionTo409WithErrorCode() {
        ConflictException ex = new ConflictException("DUPLICATE_SKU_CODE", "SKU code SKU-100 already exists");

        ProblemDetail problem = handler.handleConflictException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(problem.getTitle()).isEqualTo("Conflict");
        assertThat(problem.getDetail()).isEqualTo("SKU code SKU-100 already exists");
        assertThat(problem.getType().toString()).isEqualTo("https://problems.commerce.dev-atlas.lab/conflict");
        assertThat(problem.getProperties()).containsEntry("errorCode", "DUPLICATE_SKU_CODE");
    }

    @Test
    void shouldMapDomainExceptionTo409WithErrorCode() {
        DomainException ex = new DomainException("PRODUCT_ARCHIVED", "Archived products cannot be modified.");

        ProblemDetail problem = handler.handleDomainException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(problem.getTitle()).isEqualTo("Domain Rule Violation");
        assertThat(problem.getDetail()).isEqualTo("Archived products cannot be modified.");
        assertThat(problem.getType().toString()).isEqualTo("https://problems.commerce.dev-atlas.lab/domain-violation");
        assertThat(problem.getProperties()).containsEntry("errorCode", "PRODUCT_ARCHIVED");
    }

    @Test
    void shouldMapInfrastructureExceptionTo500AndSanitizeDetail() {
        InfrastructureException ex = new InfrastructureException(
                "DATABASE_TIMEOUT",
                "FATAL: terminating connection due to administrator command: select * from secret_keys",
                new RuntimeException("Socket timeout"));

        ProblemDetail problem = handler.handleInfrastructureException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR.value());
        assertThat(problem.getTitle()).isEqualTo("Internal Technical Failure");
        assertThat(problem.getDetail()).isEqualTo("An infrastructure error occurred while processing the request.");
        assertThat(problem.getDetail()).doesNotContain("secret_keys");
        assertThat(problem.getType().toString()).isEqualTo("https://problems.commerce.dev-atlas.lab/infrastructure-error");
        assertThat(problem.getProperties()).containsEntry("errorCode", "DATABASE_TIMEOUT");
    }

    @Test
    void shouldMapIllegalArgumentExceptionTo400WithErrorCode() {
        IllegalArgumentException ex = new IllegalArgumentException("Invalid format");

        ProblemDetail problem = handler.handleIllegalArgument(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(problem.getTitle()).isEqualTo("Bad Request");
        assertThat(problem.getDetail()).isEqualTo("Invalid format");
        assertThat(problem.getProperties()).containsEntry("errorCode", "INVALID_ARGUMENT");
    }

    @Test
    void shouldMapUnhandledExceptionTo500AndSanitizeDetail() {
        RuntimeException ex = new RuntimeException("Unexpected NullPointerException inside sensitiveMethod()");

        ProblemDetail problem = handler.handleUnhandledException(ex, request);

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR.value());
        assertThat(problem.getTitle()).isEqualTo("Internal Server Error");
        assertThat(problem.getDetail()).isEqualTo("An unexpected internal error occurred.");
        assertThat(problem.getProperties()).containsEntry("errorCode", "INTERNAL_SERVER_ERROR");
    }
}
