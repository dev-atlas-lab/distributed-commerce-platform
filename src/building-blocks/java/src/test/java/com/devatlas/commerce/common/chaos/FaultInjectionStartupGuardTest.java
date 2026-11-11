package com.devatlas.commerce.common.chaos;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class FaultInjectionStartupGuardTest {

    @Test
    void shouldFailClosedWhenFaultInjectionEnabledInProduction() {
        MockEnvironment env = new MockEnvironment()
                .withProperty("ENVIRONMENT", "production")
                .withProperty("FAULT_INJECTION_ENABLED", "true");

        FaultInjectionStartupGuard guard = new FaultInjectionStartupGuard(env);

        assertThatThrownBy(guard::verifyConfiguration)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("SECURITY_VIOLATION");
    }

    @Test
    void shouldAllowStartupWhenFaultInjectionDisabledInProduction() {
        MockEnvironment env = new MockEnvironment()
                .withProperty("ENVIRONMENT", "production")
                .withProperty("FAULT_INJECTION_ENABLED", "false");

        FaultInjectionStartupGuard guard = new FaultInjectionStartupGuard(env);

        assertThatCode(guard::verifyConfiguration).doesNotThrowAnyException();
    }

    @Test
    void shouldAllowStartupWhenFaultInjectionEnabledInChaosNonProdProfile() {
        MockEnvironment env = new MockEnvironment()
                .withProperty("ENVIRONMENT", "chaos")
                .withProperty("FAULT_INJECTION_ENABLED", "true");

        FaultInjectionStartupGuard guard = new FaultInjectionStartupGuard(env);

        assertThatCode(guard::verifyConfiguration).doesNotThrowAnyException();
    }
}
