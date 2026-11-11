package com.devatlas.commerce.common.error;

import java.util.Objects;

/**
 * Generic exception representing business rule or domain invariant violations.
 */
public class DomainException extends RuntimeException {

    private final String errorCode;

    public DomainException(ErrorCode errorCode, String message) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message);
    }

    public DomainException(ErrorCode errorCode, String message, Throwable cause) {
        this(Objects.requireNonNull(errorCode, "errorCode must not be null").code(), message, cause);
    }

    public DomainException(String errorCode, String message) {
        super(message);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public DomainException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode, "errorCode must not be null");
    }

    public String getErrorCode() {
        return errorCode;
    }
}
