package com.devatlas.commerce.payment;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the Payment Service ({@code ADR-0001}, {@code ADR-0004}).
 *
 * <p>M0.3 Source Foundation: Contains cross-cutting operational infrastructure only; business
 * domain logic begins in M1+.
 */
@SpringBootApplication
public class PaymentServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(PaymentServiceApplication.class, args);
    }
}
