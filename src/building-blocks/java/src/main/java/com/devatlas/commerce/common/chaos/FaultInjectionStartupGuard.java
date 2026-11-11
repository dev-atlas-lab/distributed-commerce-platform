package com.devatlas.commerce.common.chaos;

import java.util.Arrays;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;

/**
 * Enforces {@code CH-07} / {@code NFR-SEC-004}: Fail-closed startup guard that aborts process
 * initialization if fault injection is enabled in a production environment.
 */
public class FaultInjectionStartupGuard implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(FaultInjectionStartupGuard.class);

    private final Environment environment;

    public FaultInjectionStartupGuard(Environment environment) {
        this.environment = environment;
    }

    @Override
    public void run(ApplicationArguments args) {
        verifyConfiguration();
    }

    public void verifyConfiguration() {
        boolean faultInjectionEnabled = Boolean.parseBoolean(
                environment.getProperty("commerce.fault-injection.enabled",
                        environment.getProperty("FAULT_INJECTION_ENABLED", "false")));

        boolean productionLock = Boolean.parseBoolean(
                environment.getProperty("PRODUCTION_LOCK", "false"));

        String envName = environment.getProperty("ENVIRONMENT",
                environment.getProperty("commerce.environment", "development"))
                .toLowerCase(Locale.ROOT);

        boolean isProdProfile = Arrays.stream(environment.getActiveProfiles())
                .map(p -> p.toLowerCase(Locale.ROOT))
                .anyMatch(p -> p.equals("prod") || p.equals("production"));

        boolean isProduction = productionLock
                || envName.equals("prod")
                || envName.equals("production")
                || isProdProfile;

        if (isProduction && faultInjectionEnabled) {
            log.error("SECURITY_VIOLATION: Fault injection cannot be enabled when running in production (CH-07).");
            throw new IllegalStateException(
                    "SECURITY_VIOLATION: FAULT_INJECTION_ENABLED=true is forbidden in production environment (CH-07).");
        }
    }
}
