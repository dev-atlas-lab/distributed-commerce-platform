#!/usr/bin/env python3
"""Generates or verifies strongly-typed ErrorCode definitions across Java, .NET, and Python
from the canonical contract in docs/error-contracts/error-codes.json (ADR-0012).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = REPO_ROOT / "docs" / "error-contracts" / "error-codes.json"

JAVA_OUTPUT = (
    REPO_ROOT
    / "src"
    / "building-blocks"
    / "java"
    / "src"
    / "main"
    / "java"
    / "com"
    / "devatlas"
    / "commerce"
    / "common"
    / "error"
    / "ErrorCode.java"
)

DOTNET_OUTPUT = (
    REPO_ROOT
    / "src"
    / "building-blocks"
    / "dotnet"
    / "Commerce.BuildingBlocks"
    / "Exceptions"
    / "ErrorCode.cs"
)

PYTHON_OUTPUT = (
    REPO_ROOT
    / "src"
    / "building-blocks"
    / "python"
    / "src"
    / "commerce_common"
    / "error_codes.py"
)


def load_error_codes() -> list[dict[str, object]]:
    with CONTRACT_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return list(data.get("errorCodes", []))


def generate_java(entries: list[dict[str, object]]) -> str:
    lines = [
        "package com.devatlas.commerce.common.error;",
        "",
        "/**",
        " * Canonical cross-language error codes.",
        " * Generated from docs/error-contracts/error-codes.json. Do not edit directly.",
        " */",
        "public enum ErrorCode {",
    ]

    for i, entry in enumerate(entries):
        code = str(entry["code"])
        desc = str(entry.get("description", ""))
        sep = "," if i < len(entries) - 1 else ";"
        lines.append(f"    /** {desc} */")
        lines.append(f"    {code}(\"{code}\"){sep}")

    lines.extend([
        "",
        "    private final String code;",
        "",
        "    ErrorCode(String code) {",
        "        this.code = code;",
        "    }",
        "",
        "    public String code() {",
        "        return code;",
        "    }",
        "}",
        "",
    ])
    return "\n".join(lines)


def generate_dotnet(entries: list[dict[str, object]]) -> str:
    lines = [
        "namespace Commerce.BuildingBlocks.Exceptions;",
        "",
        "/// <summary>",
        "/// Canonical cross-language error codes.",
        "/// Generated from docs/error-contracts/error-codes.json. Do not edit directly.",
        "/// </summary>",
        "public enum ErrorCode",
        "{",
    ]

    for i, entry in enumerate(entries):
        code = str(entry["code"])
        desc = str(entry.get("description", ""))
        sep = "," if i < len(entries) - 1 else ""
        lines.append(f"    /// <summary>{desc}</summary>")
        lines.append(f"    {code}{sep}")

    lines.extend([
        "}",
        "",
        "public static class ErrorCodeExtensions",
        "{",
        "    public static string AsString(this ErrorCode errorCode) => errorCode.ToString();",
        "}",
        "",
    ])
    return "\n".join(lines)


def generate_python(entries: list[dict[str, object]]) -> str:
    lines = [
        '"""Canonical cross-language error codes.',
        'Generated from docs/error-contracts/error-codes.json. Do not edit directly.',
        '"""',
        "",
        "from __future__ import annotations",
        "",
        "from enum import StrEnum",
        "",
        "",
        "class ErrorCode(StrEnum):",
        '    """Canonical cross-language error codes."""',
        "",
    ]

    for entry in entries:
        code = str(entry["code"])
        lines.append(f'    {code} = "{code}"')

    lines.extend([
        "",
        "",
        '__all__ = ["ErrorCode"]',
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate cross-language ErrorCode classes")
    parser.add_argument("--check", action="store_true", help="Verify generated code matches contract")
    args = parser.parse_args()

    if not CONTRACT_PATH.exists():
        sys.stderr.write(f"Contract file not found: {CONTRACT_PATH}\n")
        return 1

    entries = load_error_codes()
    targets = [
        (JAVA_OUTPUT, generate_java(entries)),
        (DOTNET_OUTPUT, generate_dotnet(entries)),
        (PYTHON_OUTPUT, generate_python(entries)),
    ]

    if args.check:
        has_diff = False
        for path, expected in targets:
            if not path.exists():
                sys.stderr.write(f"Target missing: {path}\n")
                has_diff = True
                continue
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                sys.stderr.write(f"Drift detected in: {path}\n")
                has_diff = True
        if has_diff:
            sys.stderr.write("Run 'scripts/generate-error-codes.sh' to re-sync code with error-codes.json.\n")
            return 1
        print("ErrorCode definitions across Java, .NET, and Python are in sync with contract.")
        return 0

    for path, content in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"Generated: {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
