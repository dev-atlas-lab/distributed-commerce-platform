#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"

echo "=== [1/3] Building & testing Java 21 + Spring Boot 3.4 modules ==="
cd "$REPO_ROOT"
mvn -B test

echo "=== [2/3] Building & testing .NET 10 solution ==="
cd "$REPO_ROOT"
dotnet build DistributedCommerce.sln --nologo
dotnet test DistributedCommerce.sln --nologo --no-build

echo "=== [3/3] Testing, type-checking & linting Python 3.12+ AI Worker & Building Blocks ==="
cd "$REPO_ROOT/src/workers/ai-worker"
uv run --python 3.12 --extra dev pytest
uv run --python 3.12 --extra dev mypy src tests ../../building-blocks/python/src
uv run --python 3.12 --extra dev ruff check . ../../building-blocks/python

echo "=== All polyglot M0.3.1 foundation builds, type checks, and tests succeeded! ==="
