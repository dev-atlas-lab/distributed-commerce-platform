
package com.devatlas.commerce.catalog.domain.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class ProductIdTest {

    @Test
    void shouldCreateProductIdWithValidUuid() {
        UUID uuid = UUID.randomUUID();
        ProductId productId = new ProductId(uuid);
        assertThat(productId.value()).isEqualTo(uuid);
    }

    @Test
    void shouldRejectNullUuid() {
        assertThatNullPointerException().isThrownBy(() -> new ProductId(null))
                .withMessage("ProductId value must not be null");
    }

    @Test
    void shouldGenerateUniqueProductIds() {
        ProductId first = ProductId.generate();
        ProductId second = ProductId.generate();

        assertThat(first).isNotNull();
        assertThat(second).isNotNull();
        assertThat(first).isNotEqualTo(second);
        assertThat(first.value()).isNotEqualTo(second.value());
    }

    @Test
    void shouldBeEqualWhenUuidValuesAreEqual() {
        UUID uuid = UUID.randomUUID();
        ProductId first = new ProductId(uuid);
        ProductId second = new ProductId(uuid);

        assertThat(first).isEqualTo(second);
        assertThat(first.hashCode()).isEqualTo(second.hashCode());
    }

    @Test
    void shouldNotBeEqualWhenUuidValuesAreDifferent() {
        ProductId first = new ProductId(UUID.randomUUID());
        ProductId second = new ProductId(UUID.randomUUID());

        assertThat(first).isNotEqualTo(second);
    }
}
