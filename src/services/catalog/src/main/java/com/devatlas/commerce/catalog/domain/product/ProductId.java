package com.devatlas.commerce.catalog.domain.product;

import java.util.Objects;
import java.util.UUID;

public record ProductId(UUID value) {
    public ProductId {
        Objects.requireNonNull(value, "ProductId value must not be null");
    }

    public static ProductId generate() {
        return new ProductId(UUID.randomUUID());
    }
}
