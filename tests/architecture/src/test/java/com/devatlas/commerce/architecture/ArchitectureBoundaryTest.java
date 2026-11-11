package com.devatlas.commerce.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Verifies repository structure, conceptual layer presence, and Domain dependency purity
 * ({@code NFR-GOV-001}, {@code M0.3.1}).
 */
class ArchitectureBoundaryTest {

    private static final Path REPO_ROOT = Path.of("").toAbsolutePath().getParent().getParent();

    @Test
    void shouldMaintainExpectedMonorepoBoundedContextLayout() {
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
            assertThat(Files.isDirectory(REPO_ROOT.resolve(relativeDir)))
                    .as("Expected bounded context directory %s to exist", relativeDir)
                    .isTrue();
        }
    }

    @Test
    void shouldDefineConceptualArchitectureLayersForEveryService() {
        List<String> javaServices = List.of("catalog", "inventory", "order", "payment");
        for (String svc : javaServices) {
            Path basePkg = REPO_ROOT.resolve("src/services/" + svc + "/src/main/java/com/devatlas/commerce/" + svc);
            for (String layer : List.of("api", "application", "domain", "infrastructure")) {
                assertThat(Files.isDirectory(basePkg.resolve(layer)))
                        .as("Java service '%s' must contain '%s' conceptual package", svc, layer)
                        .isTrue();
            }
        }

        List<List<String>> dotnetServices = List.of(
                List.of("customer", "Commerce.Customer.Api"),
                List.of("promotion", "Commerce.Promotion.Api"),
                List.of("notification", "Commerce.Notification.Api")
        );
        for (List<String> svc : dotnetServices) {
            Path baseDir = REPO_ROOT.resolve("src/services/" + svc.get(0) + "/" + svc.get(1));
            for (String layer : List.of("Api", "Application", "Domain", "Infrastructure")) {
                assertThat(Files.isDirectory(baseDir.resolve(layer)))
                        .as(".NET service '%s' must contain '%s' conceptual folder", svc.get(0), layer)
                        .isTrue();
            }
        }

        Path pythonWorkerBase = REPO_ROOT.resolve("src/workers/ai-worker/src/ai_worker");
        for (String layer : List.of("api", "application", "domain", "infrastructure")) {
            assertThat(Files.isDirectory(pythonWorkerBase.resolve(layer)))
                    .as("Python ai-worker must contain '%s' conceptual subpackage", layer)
                    .isTrue();
        }
    }

    @Test
    void domainLayersMustNotDependOnOuterLayersOrFrameworks() throws IOException {
        List<String> forbiddenJavaTokens = List.of(
                "import org.springframework.",
                "import jakarta.persistence.",
                "import jakarta.servlet.",
                "import org.apache.kafka.",
                ".api.",
                ".application.",
                ".infrastructure."
        );

        for (String svc : List.of("catalog", "inventory", "order", "payment")) {
            Path domainDir = REPO_ROOT.resolve(
                    "src/services/" + svc + "/src/main/java/com/devatlas/commerce/" + svc + "/domain");
            assertNoForbiddenImports(domainDir, ".java", forbiddenJavaTokens);
        }

        List<String> forbiddenDotnetTokens = List.of(
                "using Microsoft.AspNetCore",
                "using Microsoft.EntityFrameworkCore",
                "using Npgsql",
                "using StackExchange.Redis",
                "using Confluent.Kafka",
                ".Api;",
                ".Application;",
                ".Infrastructure;"
        );

        for (List<String> svc : List.of(
                List.of("customer", "Commerce.Customer.Api"),
                List.of("promotion", "Commerce.Promotion.Api"),
                List.of("notification", "Commerce.Notification.Api"))) {
            Path domainDir = REPO_ROOT.resolve("src/services/" + svc.get(0) + "/" + svc.get(1) + "/Domain");
            assertNoForbiddenImports(domainDir, ".cs", forbiddenDotnetTokens);
        }

        List<String> forbiddenPythonTokens = List.of(
                "import fastapi",
                "from fastapi",
                "import sqlalchemy",
                "from sqlalchemy",
                "import openai",
                "from openai",
                "import anthropic",
                "from anthropic",
                "ai_worker.api",
                "ai_worker.application",
                "ai_worker.infrastructure"
        );
        Path pyDomainDir = REPO_ROOT.resolve("src/workers/ai-worker/src/ai_worker/domain");
        assertNoForbiddenImports(pyDomainDir, ".py", forbiddenPythonTokens);
    }

    private void assertNoForbiddenImports(Path dir, String extension, List<String> forbiddenTokens)
            throws IOException {
        try (Stream<Path> paths = Files.walk(dir)) {
            List<Path> sourceFiles = paths
                    .filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(extension))
                    .toList();
            for (Path file : sourceFiles) {
                List<String> codeLines = Files.readAllLines(file).stream()
                        .map(String::trim)
                        .filter(line -> line.startsWith("import ")
                                || line.startsWith("from ")
                                || line.startsWith("using "))
                        .toList();
                for (String line : codeLines) {
                    for (String token : forbiddenTokens) {
                        assertThat(line)
                                .as("Domain file %s must not contain forbidden import '%s'", file, token)
                                .doesNotContain(token);
                    }
                }
            }
        }
    }
}
