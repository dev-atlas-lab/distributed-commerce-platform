package com.devatlas.commerce.common.error;

import java.util.Objects;

/**
 * Generic exception representing resource or aggregate lookup failures.
 */
public class NotFoundException extends RuntimeException {

    private final String errorCode;

    public NotFoundException(ErrorCode errorCode, String message) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message);
    }

    public NotFoundException(ErrorCode errorCode, String message, Throwable cause) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message, cause);
    }

    public NotFoundException(String errorCode, String message) {
        super(message);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public NotFoundException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public String getErrorCode() {
        return errorCode;
    }
}
