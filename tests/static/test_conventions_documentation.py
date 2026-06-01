from __future__ import annotations

import ast
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONVENTIONS_DOC = REPO_ROOT / "docs" / "development" / "conventions.md"
SHARED_CONVENTIONS_DOC = REPO_ROOT / "docs" / "shared" / "development" / "conventions.md"
TEST_REF_RE = re.compile(r"`(?P<path>tests/static/test_[A-Za-z0-9_]+\.py)::(?P<name>test_[A-Za-z0-9_]+)`")


def convention_section_titles(text: str) -> list[str]:
    return [match.group(1) for match in re.finditer(r"^## ([^\n]+)$", text, flags=re.MULTILINE)]


def automated_bullets(text: str) -> list[str]:
    match = re.search(r"^## Automated\n(?P<body>.*?)(?=^## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        return []

    return [line for line in match.group("body").splitlines() if line.startswith("- ")]


def static_test_functions() -> set[str]:
    tests: set[str] = set()
    for path in sorted((REPO_ROOT / "tests" / "static").glob("test_*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        relative_path = path.relative_to(REPO_ROOT).as_posix()
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"):
                tests.add(f"{relative_path}::{node.name}")
    return tests


def referenced_static_tests(text: str) -> set[str]:
    return {f"{match.group('path')}::{match.group('name')}" for match in TEST_REF_RE.finditer(text)}


def test_conventions_document_has_required_sections() -> None:
    for path in (CONVENTIONS_DOC, SHARED_CONVENTIONS_DOC):
        assert path.is_file()

        text = path.read_text(encoding="utf-8")
        assert convention_section_titles(text) == ["Automated", "Manual"]


def test_automated_conventions_reference_existing_static_tests() -> None:
    existing_tests = static_test_functions()
    errors: list[str] = []

    for path in (CONVENTIONS_DOC, SHARED_CONVENTIONS_DOC):
        text = path.read_text(encoding="utf-8")
        for bullet in automated_bullets(text):
            references = {f"{match.group('path')}::{match.group('name')}" for match in TEST_REF_RE.finditer(bullet)}
            if not references:
                errors.append(
                    f"{path.relative_to(REPO_ROOT)} automated convention lacks a static test reference: {bullet}"
                )
                continue
            errors.extend(
                f"{path.relative_to(REPO_ROOT)} referenced static test does not exist: {reference}"
                for reference in sorted(references - existing_tests)
            )

    assert automated_bullets(CONVENTIONS_DOC.read_text(encoding="utf-8"))
    assert automated_bullets(SHARED_CONVENTIONS_DOC.read_text(encoding="utf-8"))
    assert errors == []


def test_static_tests_are_documented() -> None:
    text = CONVENTIONS_DOC.read_text(encoding="utf-8")
    assert sorted(static_test_functions() - referenced_static_tests(text)) == []
