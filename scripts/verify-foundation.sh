#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"

echo "=== [1/5] Verifying cross-language ErrorCode contract parity (docs/error-contracts/error-codes.json) ==="
python3 "$REPO_ROOT/scripts/generate-error-codes.py" --check

echo "=== [2/5] Building & testing Java 21 + Spring Boot 3.4 modules ==="
cd "$REPO_ROOT"
mvn -B test

echo "=== [3/5] Building & testing .NET 10 solution ==="
cd "$REPO_ROOT"
dotnet build DistributedCommerce.slnx --nologo
dotnet test DistributedCommerce.slnx --nologo --no-build

echo "=== [4/5] Testing, type-checking & linting Python 3.12+ AI Worker & Building Blocks ==="
cd "$REPO_ROOT/src/workers/ai-worker"
uv run --python 3.12 --extra dev pytest
uv run --python 3.12 --extra dev mypy src tests ../../building-blocks/python/src
uv run --python 3.12 --extra dev ruff check . ../../building-blocks/python

echo "=== [5/5] Type-checking, testing & building React 19 Frontend Shell ==="
cd "$REPO_ROOT/frontend"
npm run typecheck
npm run test
npm run build

echo "=== All polyglot M1 foundation builds, type checks, and tests succeeded! ==="
