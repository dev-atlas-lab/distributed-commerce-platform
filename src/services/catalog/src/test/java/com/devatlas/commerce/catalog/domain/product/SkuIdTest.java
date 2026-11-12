
package com.devatlas.commerce.catalog.domain.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class SkuIdTest {

    @Test
    void shouldCreateSkuIdWithValidUuid() {
        UUID uuid = UUID.randomUUID();
        SkuId id = new SkuId(uuid);
        assertThat(id.value()).isEqualTo(uuid);
    }

    @Test
    void shouldRejectNullUuid() {
        assertThatNullPointerException()
                .isThrownBy(() -> new SkuId(null))
                .withMessage("SkuId value must not be null");
    }

    @Test
    void shouldGenerateUniqueSkuIds() {
        SkuId first = SkuId.generate();
        SkuId second = SkuId.generate();

        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void shouldHaveValueBasedEquality() {
        UUID uuid = UUID.randomUUID();
        SkuId first = new SkuId(uuid);
        SkuId second = new SkuId(uuid);

        assertThat(first).isEqualTo(second);
        assertThat(first.hashCode()).isEqualTo(second.hashCode());
    }

    @Test
    void shouldNotBeEqualWhenUuidValuesAreDifferent() {
        SkuId first = SkuId.generate();
        SkuId second = SkuId.generate();

        assertThat(first).isNotEqualTo(second);
    }
}
