#!/usr/bin/env python3
"""Fail-closed schema check for usecases/*.yaml.

terraform/environments/dev/main.tf's `use_case = { ... }` object construction
only ever COPIES named fields out of the decoded YAML - an extra key (e.g. a
team adding `spec.provider: openai`, believing it takes effect) is invisible
to that construction, so a clean `terraform plan` would otherwise be the only
feedback a team gets, and it would be silently wrong. This is a second,
independent enforcement of the same contract shape that main.tf's own
`terraform_data.advisor_chat_contract_shape` `lifecycle precondition`
enforces at plan time - this script is a static, credential-free check any
contributor (or CI's policy-tests job) can run without `terraform init`.

Deliberately NOT a general YAML parser: stdlib has none, and this repo's
tests/policy scripts are stdlib-only by design so CI needs no install step
(see spend_quality_checks.py's header). usecases/*.yaml declarations are
constrained by design to a flat, two-level shape - top-level
keys, and one level of children under `metadata`/`spec` - which a simple
indentation-based scanner can extract correctly without needing to parse
scalar values, lists, anchors, or arbitrary nesting.

    python3 tests/policy/usecase_schema_checks.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
USECASE_FILES = sorted(REPO_ROOT.glob("usecases/*.yaml"))

EXPECTED_TOP_LEVEL_KEYS = {"apiVersion", "kind", "metadata", "spec"}
EXPECTED_METADATA_KEYS = {"id", "owner", "team"}
EXPECTED_SPEC_KEYS = {"dataClassification", "modelRoute", "budget", "observability"}
EXPECTED_API_VERSION = "ai-platform.example.com/v1"
EXPECTED_KIND = "AIUseCase"

_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")


def extract_shape(text: str) -> dict[str, object]:
    """Returns top-level keys/values plus metadata/spec child key sets."""
    top_level: dict[str, str] = {}
    section_keys: dict[str, set[str]] = {"metadata": set(), "spec": set()}
    current_section: str | None = None
    child_indent: int | None = None

    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        match = _KEY_RE.match(line.strip())
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip()

        if indent == 0:
            top_level[key] = value
            current_section = key if key in section_keys else None
            child_indent = None
            continue

        if current_section is not None:
            if child_indent is None:
                child_indent = indent
            if indent == child_indent:
                section_keys[current_section].add(key)
            # A deeper indent (e.g. spec.budget.monthlyUsd) is a grandchild,
            # not a direct metadata/spec key - out of scope for this check.

    return {
        "top_level_keys": set(top_level.keys()),
        "api_version": top_level.get("apiVersion"),
        "kind": top_level.get("kind"),
        "metadata_keys": section_keys["metadata"],
        "spec_keys": section_keys["spec"],
    }


def check_shape(text: str, label: str) -> list[str]:
    """Returns a list of failure messages; empty means the shape is valid."""
    shape = extract_shape(text)
    failures: list[str] = []

    unknown_top = shape["top_level_keys"] - EXPECTED_TOP_LEVEL_KEYS
    if unknown_top:
        failures.append(f"{label}: unknown top-level key(s): {sorted(unknown_top)}")

    if shape["api_version"] != EXPECTED_API_VERSION:
        failures.append(f"{label}: apiVersion must be {EXPECTED_API_VERSION!r}, got {shape['api_version']!r}")

    if shape["kind"] != EXPECTED_KIND:
        failures.append(f"{label}: kind must be {EXPECTED_KIND!r}, got {shape['kind']!r}")

    unknown_metadata = shape["metadata_keys"] - EXPECTED_METADATA_KEYS
    if unknown_metadata:
        failures.append(f"{label}: unknown metadata key(s): {sorted(unknown_metadata)}")

    unknown_spec = shape["spec_keys"] - EXPECTED_SPEC_KEYS
    if unknown_spec:
        failures.append(f"{label}: unknown spec key(s): {sorted(unknown_spec)}")

    return failures


# Negative-test fixture - a real use-case declaration's shape with one
# unapproved field added, exactly the scenario this whole check exists for.
_BAD_SPEC_PROVIDER_FIXTURE = """
apiVersion: ai-platform.example.com/v1
kind: AIUseCase

metadata:
  id: shadow-provider-example
  owner: someone
  team: someone

spec:
  dataClassification: internal
  modelRoute: anthropic-claude-haiku-bedrock
  provider: openai
  budget:
    monthlyUsd: 100
  observability:
    tier: minimal
"""


def main() -> int:
    failures: list[str] = []

    if not USECASE_FILES:
        print("FAIL: no usecases/*.yaml files found.")
        return 1

    for path in USECASE_FILES:
        text = path.read_text(encoding="utf-8")
        file_failures = check_shape(text, str(path.relative_to(REPO_ROOT)))
        if file_failures:
            failures.extend(file_failures)
        else:
            print(f"OK: {path.relative_to(REPO_ROOT)} matches the expected contract shape.")

    # Negative test: the checker function must actually catch the one
    # field this whole script exists to catch.
    fixture_failures = check_shape(_BAD_SPEC_PROVIDER_FIXTURE, "fixture")
    if not any("provider" in f for f in fixture_failures):
        failures.append(
            "negative-test fixture with spec.provider did NOT get flagged - "
            f"the schema checker itself is broken. Got failures: {fixture_failures}"
        )
    else:
        print("OK: negative-test fixture (spec.provider) correctly flagged as an unknown key.")

    if failures:
        print("\nFAIL:")
        for f in failures:
            print(f"  - {f}")
        return 1

    print("\nPASS: every usecases/*.yaml declaration matches the expected contract shape.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
