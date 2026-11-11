package com.devatlas.commerce.common.error;

import java.util.Objects;

/**
 * Generic exception representing technical failures from external dependencies or infrastructure.
 */
public class InfrastructureException extends RuntimeException {

    private final String errorCode;

    public InfrastructureException(ErrorCode errorCode, String message) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message);
    }

    public InfrastructureException(ErrorCode errorCode, String message, Throwable cause) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message, cause);
    }

    public InfrastructureException(String errorCode, String message) {
        super(message);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public InfrastructureException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public String getErrorCode() {
        return errorCode;
    }
}
