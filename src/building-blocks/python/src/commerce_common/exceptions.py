"""Generic exception taxonomy for Commerce platform (Python 3.12+)."""

from __future__ import annotations

from .error_codes import ErrorCode


class DomainException(Exception):
    """Generic exception representing business rule or domain invariant violations."""

    def __init__(self, error_code: ErrorCode | str, message: str) -> None:
        super().__init__(message)
        resolved_code = str(error_code.value) if isinstance(error_code, ErrorCode) else str(error_code)
        if not resolved_code:
            raise ValueError("error_code must not be empty")
        self.error_code: str = resolved_code
        self.message: str = message


class ValidationException(Exception):
    """Generic exception representing invalid input data or violated validation constraints."""

    def __init__(self, error_code: ErrorCode | str, message: str) -> None:
        super().__init__(message)
        resolved_code = str(error_code.value) if isinstance(error_code, ErrorCode) else str(error_code)
        if not resolved_code:
            raise ValueError("error_code must not be empty")
        self.error_code: str = resolved_code
        self.message: str = message


class NotFoundException(Exception):
    """Generic exception representing resource or aggregate lookup failures."""

    def __init__(self, error_code: ErrorCode | str, message: str) -> None:
        super().__init__(message)
        resolved_code = str(error_code.value) if isinstance(error_code, ErrorCode) else str(error_code)
        if not resolved_code:
            raise ValueError("error_code must not be empty")
        self.error_code: str = resolved_code
        self.message: str = message


class ConflictException(Exception):
    """Generic exception representing state conflicts such as version mismatch or duplicate constraints."""

    def __init__(self, error_code: ErrorCode | str, message: str) -> None:
        super().__init__(message)
        resolved_code = str(error_code.value) if isinstance(error_code, ErrorCode) else str(error_code)
        if not resolved_code:
            raise ValueError("error_code must not be empty")
        self.error_code: str = resolved_code
        self.message: str = message


class InfrastructureException(Exception):
    """Generic exception representing technical failures from external dependencies or infrastructure."""

    def __init__(self, error_code: ErrorCode | str, message: str) -> None:
        super().__init__(message)
        resolved_code = str(error_code.value) if isinstance(error_code, ErrorCode) else str(error_code)
        if not resolved_code:
            raise ValueError("error_code must not be empty")
        self.error_code: str = resolved_code
        self.message: str = message
