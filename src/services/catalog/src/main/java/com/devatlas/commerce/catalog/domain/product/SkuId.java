package com.devatlas.commerce.catalog.domain.product;

import java.util.Objects;
import java.util.UUID;

public record SkuId(UUID value) {
    public SkuId {
        Objects.requireNonNull(value, "SkuId value must not be null");
    }

    public static SkuId generate() {
        return new SkuId(UUID.randomUUID());
    }
}
