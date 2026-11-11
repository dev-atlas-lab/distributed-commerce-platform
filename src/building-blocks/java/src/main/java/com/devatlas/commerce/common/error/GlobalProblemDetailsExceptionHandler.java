package com.devatlas.commerce.common.error;

import com.devatlas.commerce.common.observability.CorrelationIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Standardizes generic application, domain, and unhandled exceptions into RFC 9457
 * {@link ProblemDetail} responses ({@code NFR-OBS-002}).
 */
@RestControllerAdvice
public class GlobalProblemDetailsExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalProblemDetailsExceptionHandler.class);

    private static final String DEFAULT_INFRASTRUCTURE_DETAIL =
            "An infrastructure error occurred while processing the request.";
    private static final String DEFAULT_UNHANDLED_DETAIL =
            "An unexpected internal error occurred.";

    @ExceptionHandler(ValidationException.class)
    public ProblemDetail handleValidationException(ValidationException ex, HttpServletRequest request) {
        log.warn("Validation error [{}]: {}", ex.getErrorCode(), ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
        problem.setTitle("Bad Request");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/validation-error"));
        enrichProblemDetail(problem, request, ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(NotFoundException.class)
    public ProblemDetail handleNotFoundException(NotFoundException ex, HttpServletRequest request) {
        log.warn("Resource not found [{}]: {}", ex.getErrorCode(), ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Not Found");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/not-found"));
        enrichProblemDetail(problem, request, ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(ConflictException.class)
    public ProblemDetail handleConflictException(ConflictException ex, HttpServletRequest request) {
        log.warn("State conflict [{}]: {}", ex.getErrorCode(), ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Conflict");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/conflict"));
        enrichProblemDetail(problem, request, ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(DomainException.class)
    public ProblemDetail handleDomainException(DomainException ex, HttpServletRequest request) {
        log.warn("Domain rule violation [{}]: {}", ex.getErrorCode(), ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Domain Rule Violation");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/domain-violation"));
        enrichProblemDetail(problem, request, ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(InfrastructureException.class)
    public ProblemDetail handleInfrastructureException(InfrastructureException ex, HttpServletRequest request) {
        log.error("Infrastructure technical failure [{}]: {}", ex.getErrorCode(), ex.getMessage(), ex);
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.INTERNAL_SERVER_ERROR,
                DEFAULT_INFRASTRUCTURE_DETAIL);
        problem.setTitle("Internal Technical Failure");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/infrastructure-error"));
        enrichProblemDetail(problem, request, ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail handleIllegalArgument(IllegalArgumentException ex, HttpServletRequest request) {
        log.warn("Invalid argument: {}", ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
        problem.setTitle("Bad Request");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/bad-request"));
        enrichProblemDetail(problem, request, "INVALID_ARGUMENT");
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnhandledException(Exception ex, HttpServletRequest request) {
        log.error("Unhandled internal server exception", ex);
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.INTERNAL_SERVER_ERROR,
                DEFAULT_UNHANDLED_DETAIL);
        problem.setTitle("Internal Server Error");
        problem.setType(URI.create("https://problems.commerce.dev-atlas.lab/internal-error"));
        enrichProblemDetail(problem, request, "INTERNAL_SERVER_ERROR");
        return problem;
    }

    private void enrichProblemDetail(ProblemDetail problem, HttpServletRequest request, String errorCode) {
        if (request != null && request.getRequestURI() != null) {
            problem.setInstance(URI.create(request.getRequestURI()));
        }
        problem.setProperty("errorCode", errorCode);
        problem.setProperty("timestamp", Instant.now().toString());

        String correlationId = MDC.get(CorrelationIdFilter.CORRELATION_ID_MDC_KEY);
        if (correlationId == null && request != null) {
            correlationId = request.getHeader(CorrelationIdFilter.CORRELATION_ID_HEADER);
        }
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }

        String traceId = MDC.get("traceId");
        if (traceId == null) {
            traceId = correlationId;
        }
        if (traceId != null) {
            problem.setProperty("traceId", traceId);
        }
    }
}
