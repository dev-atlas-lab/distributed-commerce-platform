package com.devatlas.commerce.catalog.domain.product;

import java.util.Objects;
import java.util.UUID;

public record CategoryId(UUID value) {
    public CategoryId {
        Objects.requireNonNull(value, "CategoryId value must not be null");
    }

    public static CategoryId generate() {
        return new CategoryId(UUID.randomUUID());
    }
}
