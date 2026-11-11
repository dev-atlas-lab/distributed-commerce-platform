/**
 * Pure Domain layer for Order Service (Order aggregate, explicit transition matrix, Saga state, repository ports).
 *
 * <p>Must have ZERO dependencies on Spring, JPA/JDBC, Kafka, Redis, or outer layers ({@code api},
 * {@code application}, {@code infrastructure}).
 */
package com.devatlas.commerce.order.domain;
