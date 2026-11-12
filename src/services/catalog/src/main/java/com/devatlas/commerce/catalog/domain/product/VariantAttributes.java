package com.devatlas.commerce.catalog.domain.product;

import java.util.Map;

import com.devatlas.commerce.common.error.ErrorCode;
import com.devatlas.commerce.common.error.ValidationException;

import java.util.HashMap;
import java.util.Collections;

public record VariantAttributes(Map<String, String> values) {

    public VariantAttributes {
        if (values == null) {
            throw new ValidationException(ErrorCode.INVALID_ATTRIBUTES, "Variant attributes cannot be null");
        }

        Map<String, String> normalizedValues = new HashMap<>();

        values.forEach((key, value) -> {
            if (key == null || key.isBlank()) {
                throw new ValidationException(ErrorCode.INVALID_ATTRIBUTES,
                        "Variant attribute key cannot be null or blank");
            }

            if (value == null || value.isBlank()) {
                throw new ValidationException(ErrorCode.INVALID_ATTRIBUTES,
                        "Variant attribute value cannot be null or blank");
            }

            normalizedValues.put(key.trim(), value.trim());
        });

        values = Collections.unmodifiableMap(normalizedValues);
    }

    public static VariantAttributes empty() {
        return new VariantAttributes(Map.of());
    }
}