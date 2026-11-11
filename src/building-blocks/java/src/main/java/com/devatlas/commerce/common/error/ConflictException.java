package com.devatlas.commerce.common.error;

import java.util.Objects;

/**
 * Generic exception representing state conflicts such as version mismatch or duplicate constraints.
 */
public class ConflictException extends RuntimeException {

    private final String errorCode;

    public ConflictException(ErrorCode errorCode, String message) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message);
    }

    public ConflictException(ErrorCode errorCode, String message, Throwable cause) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message, cause);
    }

    public ConflictException(String errorCode, String message) {
        super(message);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public ConflictException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public String getErrorCode() {
        return errorCode;
    }
}
