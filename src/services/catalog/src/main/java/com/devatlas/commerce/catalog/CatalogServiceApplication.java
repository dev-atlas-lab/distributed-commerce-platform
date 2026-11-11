package com.devatlas.commerce.catalog;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the Catalog Service ({@code ADR-0001}, {@code ADR-0007}).
 *
 * <p>M0.3 Source Foundation: Contains cross-cutting operational infrastructure only; business
 * domain logic begins in M1+.
 */
@SpringBootApplication
public class CatalogServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(CatalogServiceApplication.class, args);
    }
}
