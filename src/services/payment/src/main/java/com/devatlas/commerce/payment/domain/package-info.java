/**
 * Pure Domain layer for Payment Service (PaymentAttempt & Refund state machines, transition validation, repository ports).
 *
 * <p>Must have ZERO dependencies on Spring, JPA/JDBC, Kafka, Redis, or outer layers ({@code api},
 * {@code application}, {@code infrastructure}).
 */
package com.devatlas.commerce.payment.domain;
