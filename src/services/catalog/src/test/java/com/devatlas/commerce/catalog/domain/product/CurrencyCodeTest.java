package com.devatlas.commerce.catalog.domain.product;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

public class CurrencyCodeTest {

    @Test
    void shouldReturnCorrectFractionDigitsForUsd() {
        assertThat(CurrencyCode.USD.fractionDigits()).isEqualTo(2);
    }

    @Test
    void shouldReturnCorrectFractionDigitsForVnd() {
        assertThat(CurrencyCode.VND.fractionDigits()).isEqualTo(0);
    }

    @Test
    void shouldContainExpectedCurrencyCodes() {
        assertThat(CurrencyCode.values()).containsExactly(CurrencyCode.USD, CurrencyCode.VND);
    }

    @Test
    void shouldResolveCurrencyCodeByName() {
        assertThat(CurrencyCode.valueOf("USD")).isEqualTo(CurrencyCode.USD);
        assertThat(CurrencyCode.valueOf("VND")).isEqualTo(CurrencyCode.VND);
    }
}
