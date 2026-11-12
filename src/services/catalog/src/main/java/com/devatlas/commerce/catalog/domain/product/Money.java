package com.devatlas.commerce.catalog.domain.product;

import java.math.BigDecimal;

import com.devatlas.commerce.common.error.ErrorCode;
import com.devatlas.commerce.common.error.ValidationException;

public record Money(BigDecimal amount, CurrencyCode currencyCode) {
    public Money {
        if (amount == null) {
            throw new ValidationException(ErrorCode.INVALID_MONEY_AMOUNT, "Money amount cannot be null.");
        }

        if (currencyCode == null) {
            throw new ValidationException(ErrorCode.INVALID_MONEY_AMOUNT, "Currency code cannot be null.");
        }

        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new ValidationException(ErrorCode.INVALID_MONEY_AMOUNT, "Money amount must be greater than zero.");
        }

        if (amount.scale() > currencyCode.fractionDigits()) {
            throw new ValidationException(ErrorCode.INVALID_MONEY_AMOUNT,
                    "Money amount exceeds allowed decimal scale for currency.");
        }
    }
}
