package com.devatlas.commerce.catalog.domain.product;

import java.util.Objects;
import java.util.UUID;

public record MediaId(UUID value) {
    public MediaId {
        Objects.requireNonNull(value, "MediaId value must not be null");
    }

    public static MediaId generate() {
        return new MediaId(UUID.randomUUID());
    }
}
