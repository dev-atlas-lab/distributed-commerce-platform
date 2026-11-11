package com.devatlas.commerce.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the Inventory Service ({@code ADR-0001}, {@code ADR-0005}).
 *
 * <p>M0.3 Source Foundation: Contains cross-cutting operational infrastructure only; business
 * domain logic begins in M1+.
 */
@SpringBootApplication
public class InventoryServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(InventoryServiceApplication.class, args);
    }
}
