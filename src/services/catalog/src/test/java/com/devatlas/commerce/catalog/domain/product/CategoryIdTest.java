
package com.devatlas.commerce.catalog.domain.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class CategoryIdTest {

    @Test
    void shouldCreateCategoryIdWithValidUuid() {
        UUID uuid = UUID.randomUUID();
        CategoryId id = new CategoryId(uuid);
        assertThat(id.value()).isEqualTo(uuid);
    }

    @Test
    void shouldRejectNullUuid() {
        assertThatNullPointerException()
                .isThrownBy(() -> new CategoryId(null))
                .withMessage("CategoryId value must not be null");
    }

    @Test
    void shouldGenerateUniqueCategoryIds() {
        CategoryId first = CategoryId.generate();
        CategoryId second = CategoryId.generate();
        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void shouldHaveValueBasedEquality() {
        UUID uuid = UUID.randomUUID();
        CategoryId first = new CategoryId(uuid);
        CategoryId second = new CategoryId(uuid);

        assertThat(first).isEqualTo(second);
        assertThat(first.hashCode()).isEqualTo(second.hashCode());
    }

    @Test
    void shouldNotBeEqualWhenUuidValuesAreDifferent() {
        CategoryId first = CategoryId.generate();
        CategoryId second = CategoryId.generate();

        assertThat(first).isNotEqualTo(second);
    }
}
