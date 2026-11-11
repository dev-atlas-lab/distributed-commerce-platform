/**
 * Pure Domain layer for Inventory Service (stock items, reservations, ledger invariants, repository ports).
 *
 * <p>Must have ZERO dependencies on Spring, JPA/JDBC, Kafka, Redis, or outer layers ({@code api},
 * {@code application}, {@code infrastructure}).
 */
package com.devatlas.commerce.inventory.domain;
