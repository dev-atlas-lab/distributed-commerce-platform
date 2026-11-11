package com.devatlas.commerce.order;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the Order Service ({@code ADR-0001}, {@code ADR-0004}).
 *
 * <p>M0.3 Source Foundation: Contains cross-cutting operational infrastructure only; business
 * domain logic begins in M1+.
 */
@SpringBootApplication
public class OrderServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderServiceApplication.class, args);
    }
}
