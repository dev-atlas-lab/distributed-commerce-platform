package com.devatlas.commerce.common.autoconfig;

import com.devatlas.commerce.common.chaos.FaultInjectionStartupGuard;
import com.devatlas.commerce.common.error.GlobalProblemDetailsExceptionHandler;
import com.devatlas.commerce.common.observability.CorrelationIdFilter;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.core.env.Environment;

/**
 * Auto-configuration registering cross-cutting platform building blocks across Java services.
 */
@AutoConfiguration
public class CommerceCommonAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public CorrelationIdFilter correlationIdFilter() {
        return new CorrelationIdFilter();
    }

    @Bean
    @ConditionalOnMissingBean
    public GlobalProblemDetailsExceptionHandler globalProblemDetailsExceptionHandler() {
        return new GlobalProblemDetailsExceptionHandler();
    }

    @Bean
    @ConditionalOnMissingBean
    public FaultInjectionStartupGuard faultInjectionStartupGuard(Environment environment) {
        return new FaultInjectionStartupGuard(environment);
    }
}
