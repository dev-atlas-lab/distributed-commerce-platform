package com.devatlas.commerce.catalog.domain.product;

import com.devatlas.commerce.common.error.ErrorCode;
import com.devatlas.commerce.common.error.ValidationException;

import java.util.Locale;
import java.util.regex.Pattern;

public record SkuCode(String value) {

    private static final Pattern SKU_PATTERN = Pattern.compile("^[A-Z0-9][A-Z0-9_-]{2,63}$");

    public SkuCode {
        if (value == null || value.isBlank()) {
            throw new ValidationException(
                    ErrorCode.INVALID_SKU_CODE,
                    "SkuCode cannot be null or blank");
        }

        value = value.trim().toUpperCase(Locale.ROOT);

        if (!SKU_PATTERN.matcher(value).matches()) {
            throw new ValidationException(ErrorCode.INVALID_SKU_CODE,
                    String.format("Invalid SKU code format: %s", value));
        }
    }
}
