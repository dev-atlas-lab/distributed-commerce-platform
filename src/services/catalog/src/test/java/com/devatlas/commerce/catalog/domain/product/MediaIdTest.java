
package com.devatlas.commerce.catalog.domain.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class MediaIdTest {

    @Test
    void shouldCreateMediaIdWithValidUuid() {
        UUID uuid = UUID.randomUUID();
        MediaId id = new MediaId(uuid);
        assertThat(id.value()).isEqualTo(uuid);
    }

    @Test
    void shouldRejectNullUuid() {
        assertThatNullPointerException()
                .isThrownBy(() -> new MediaId(null))
                .withMessage("MediaId value must not be null");
    }

    @Test
    void shouldGenerateUniqueMediaIds() {
        MediaId first = MediaId.generate();
        MediaId second = MediaId.generate();

        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void shouldHaveValueBasedEquality() {
        UUID uuid = UUID.randomUUID();
        MediaId first = new MediaId(uuid);
        MediaId second = new MediaId(uuid);

        assertThat(first).isEqualTo(second);
        assertThat(first.hashCode()).isEqualTo(second.hashCode());
    }

    @Test
    void shouldNotBeEqualWhenUuidValuesAreDifferent() {
        MediaId first = MediaId.generate();
        MediaId second = MediaId.generate();

        assertThat(first).isNotEqualTo(second);
    }
}
