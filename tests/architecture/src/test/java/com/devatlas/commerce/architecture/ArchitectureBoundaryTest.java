package com.devatlas.commerce.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Verifies repository structure and service boundary isolation ({@code NFR-GOV-001}).
 */
class ArchitectureBoundaryTest {

    @Test
    void shouldMaintainExpectedMonorepoBoundedContextLayout() {
        Path repoRoot = Path.of("").toAbsolutePath().getParent().getParent();
        List<String> requiredDirectories = List.of(
                "src/gateways/api-gateway",
                "src/services/catalog",
                "src/services/inventory",
                "src/services/order",
                "src/services/payment",
                "src/services/customer",
                "src/services/promotion",
                "src/services/notification",
                "src/workers/ai-worker",
                "src/building-blocks/java",
                "src/building-blocks/dotnet",
                "src/building-blocks/python",
                "docs/architecture",
                "docs/requirements",
                "docs/adr"
        );

        for (String relativeDir : requiredDirectories) {
            assertThat(Files.isDirectory(repoRoot.resolve(relativeDir)))
                    .as("Expected bounded context directory %s to exist", relativeDir)
                    .isTrue();
        }
    }
}
