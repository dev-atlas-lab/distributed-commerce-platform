package com.devatlas.commerce.inventory.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfiguration {

    @Bean
    public OpenAPI inventoryServiceOpenApi() {
        return new OpenAPI()
                .info(new Info()
                        .title("Inventory Service API")
                        .version("v1")
                        .description("SKU Stock Ledger & Reservation bounded context API (M0.3 Foundation)"));
    }
}
