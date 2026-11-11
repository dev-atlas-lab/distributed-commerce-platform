package com.devatlas.commerce.common.error;

import java.util.Objects;

/**
 * Generic exception representing invalid input data or violated validation constraints.
 */
public class ValidationException extends RuntimeException {

    private final String errorCode;

    public ValidationException(ErrorCode errorCode, String message) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message);
    }

    public ValidationException(ErrorCode errorCode, String message, Throwable cause) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message, cause);
    }

    public ValidationException(String errorCode, String message) {
        super(message);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public ValidationException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public String getErrorCode() {
        return errorCode;
    }
}
