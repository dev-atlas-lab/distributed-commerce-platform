package com.devatlas.commerce.catalog.domain.product;

public enum CurrencyCode {

    USD(2),
    VND(0);

    private final int fractionDigits;

    CurrencyCode(int fractionDigits) {
        this.fractionDigits = fractionDigits;
    }

    public int fractionDigits() {
        return fractionDigits;
    }
}
