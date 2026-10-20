#!/usr/bin/env python3
"""Dead-path and tracker-ID guard for reader-facing docs.

Two independent checks, both dumb stdlib-only text scans rather than a
Terraform-aware resolver:

1. **Dead paths.** A round of module extractions moved or deleted a lot of
   Terraform files. This catches the next round of that same drift: a
   `.md`/`.mmd`/`.tf`/`.yml`/`.sh` file pointing at a `terraform/...`,
   `tests/...`, `scripts/...`, `docs/...` or `diagrams/...` path, or a bare
   `*.tf` filename, that no longer exists anywhere in the repo.

   Deliberately no directory-of-mention awareness for bare filenames (e.g.
   it won't catch "ecs.tf" being mentioned in a file where the real
   `ecs.tf` is a different one three directories over) - it only checks
   that a file by that basename exists *somewhere*. That's enough to catch
   a fully-deleted file without becoming a full path resolver.

   A small, explicit allowlist covers references that are correctly
   historical ("moved from ci_roles.tf", "the former demo_stack.tf", etc.)
   - anything not on it must resolve.

2. **Tracker IDs.** Reader-facing docs (README.md, design.md,
   architecture.md, terraform/modules/*/README.md,
   diagrams/*.mmd) should read standalone - a reader shouldn't need to
   resolve an internal `S<n>.<n>`/`E<n>`/`M<n>`/`#<n>` story or issue
   number to understand them. Internal planning docs (CLAUDE.md,
   docs/demo-runtime-evidence.md's dated log) are
   exempt - those are exactly where that context belongs.

    python3 tests/policy/doc_path_refs.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

SCAN_EXTENSIONS = {".md", ".mmd", ".tf", ".yml", ".sh"}

# Directories never worth descending into for this scan.
EXCLUDED_DIR_NAMES = {
    ".git",
    ".claude",
    ".agents",
    ".terraform",
    "node_modules",
}

# Path-prefixed references: "terraform/foo/bar.tf", "docs/x.md", etc.
# The lookbehind skips a prefix that is itself the tail of a longer path
# or name (e.g. "asci-doc/scripts/build.sh" is not the root "scripts/").
PATH_PATTERN = re.compile(
    r"(?<![\w/\-])(?:terraform|tests|scripts|docs|diagrams)/[A-Za-z0-9_./\-]+"
)

# Bare *.tf filename mentions, e.g. "ecs.tf" or "`langfuse.tf`" with no
# directory component (those are caught by PATH_PATTERN instead).
BARE_TF_PATTERN = re.compile(r"(?<![\w/\-])([A-Za-z0-9_\-]+\.tf)\b")

# Trailing punctuation that regularly rides along with a markdown/backtick
# reference and isn't part of the path itself.
TRAILING_PUNCTUATION = ".,;:'\")]}`"

# Each entry here is a verified-intentional historical mention, not a real
# dead link.
ALLOWLIST: set[tuple[str, str]] = {
    ("terraform/environments/dev/variables.tf", "ci_roles.tf"),
    ("terraform/environments/dev/variables.tf", "langfuse.tf"),
    ("terraform/environments/dev/outputs.tf", "datadog.tf"),
    ("terraform/environments/dev/outputs.tf", "demo_stack.tf"),
    ("terraform/environments/dev/main.tf", "datadog.tf"),
    ("terraform/environments/dev/main.tf", "budget_alarms.tf"),
    (
        "terraform/modules/llm-gateway/secrets.tf",
        "terraform/environments/dev/langfuse.tf",
    ),
    (
        "terraform/modules/use-case-observability/variables.tf",
        "terraform/environments/dev/datadog.tf",
    ),
    ("terraform/modules/use-case-observability/variables.tf", "budget_alarms.tf"),
    (
        "terraform/modules/use-case-observability/README.md",
        "terraform/environments/dev/datadog.tf",
    ),
    ("terraform/modules/use-case-observability/README.md", "budget_alarms.tf"),
    (
        "terraform/modules/use-case-observability/budget.tf",
        "terraform/environments/dev/budget_alarms.tf",
    ),
    ("README.md", "datadog.tf"),
    ("README.md", "budget_alarms.tf"),
    ("terraform/modules/llm-gateway/README.md", "demo_stack.tf"),
    ("docs/demo-runtime-evidence.md", "terraform/environments/dev/demo_stack.tf"),
    ("docs/demo-runtime-evidence.md", "demo_stack.tf"),
    ("docs/demo-runtime-evidence.md", "terraform/environments/dev/langfuse.tf"),
    ("docs/demo-runtime-evidence.md", "langfuse.tf"),
    ("CLAUDE.md", "terraform/environments/dev/langfuse.tf"),
    ("terraform/modules/llm-gateway/ecs.tf", "terraform/environments/dev/ecs.tf"),
    ("terraform/modules/llm-gateway/rds.tf", "terraform/environments/dev/rds.tf"),
    (
        "terraform/modules/llm-gateway/secrets.tf",
        "terraform/modules/use-case/secrets.tf",
    ),
    # The gateway's provisioning script lives under the environment root's
    # own `scripts/` subdirectory, not the repo-root scripts/ dir a naive
    # prefix match would expect.
    (
        "terraform/environments/dev/virtual_key.tf",
        "scripts/ensure_virtual_key.sh",
    ),
    # Historical log entry (S31.1 renamed the script; this is a captured
    # transcript of what it printed under its old name at the time).
    (
        "docs/demo-runtime-evidence.md",
        "terraform/environments/dev/scripts/ensure_advisorchat_virtual_key.sh",
    ),
    (".github/workflows/terraform.yml", "terraform/environments/dev/tfplan"),
}

# Reader-facing docs that must read standalone, with no internal tracker ID.
TRACKER_ID_FREE_GLOBS = [
    "README.md",
    "design.md",
    "architecture.md",
    "terraform/modules/*/README.md",
    "diagrams/*.mmd",
]

# A tracker ID (S1.2, E30, M16, #142) as a whole word/token - not, for
# example, a hex color (#374151) or a model version (MiniMax M2.5).
TRACKER_ID_PATTERN = re.compile(
    r"\bS[0-9]+\.[0-9]+\b|\bE[0-9]{1,3}\b|\bM[0-9]{1,3}\b(?!\.[0-9])|[( ]#[0-9]{1,4}\b"
)


def iter_tracker_id_checked_files():
    seen: set[Path] = set()
    for pattern in TRACKER_ID_FREE_GLOBS:
        for path in REPO_ROOT.glob(pattern):
            if path.is_file() and path not in seen:
                seen.add(path)
                yield path


def iter_scan_files():
    for path in REPO_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in SCAN_EXTENSIONS:
            continue
        if any(part in EXCLUDED_DIR_NAMES for part in path.relative_to(REPO_ROOT).parts):
            continue
        yield path


def strip_trailing_punctuation(ref: str) -> str:
    return ref.rstrip(TRAILING_PUNCTUATION)


def reference_exists(ref: str) -> bool:
    if "/" in ref:
        return (REPO_ROOT / ref).exists()
    # Bare filename: exists anywhere in the repo (see module docstring).
    return any(True for _ in REPO_ROOT.rglob(ref))


def main() -> int:
    failures: list[str] = []
    files_scanned = 0

    for path in iter_scan_files():
        files_scanned += 1
        rel_path = str(path.relative_to(REPO_ROOT))
        text = path.read_text(encoding="utf-8", errors="ignore")

        for line_no, line in enumerate(text.splitlines(), start=1):
            candidates: list[str] = []
            candidates += PATH_PATTERN.findall(line)
            candidates += BARE_TF_PATTERN.findall(line)

            for raw_ref in candidates:
                ref = strip_trailing_punctuation(raw_ref)
                if not ref:
                    continue
                # A path ending in a bare hyphen is a
                # hyphenated word wrapped across a line break
                # in prose, not a real reference with a
                # legitimately unresolvable tail.
                if ref.endswith("-"):
                    continue
                if reference_exists(ref):
                    continue
                if (rel_path, ref) in ALLOWLIST:
                    continue
                failures.append(f"{rel_path}:{line_no}: dead reference '{ref}'")

    tracker_id_failures: list[str] = []
    tracker_id_files_scanned = 0

    for path in iter_tracker_id_checked_files():
        tracker_id_files_scanned += 1
        rel_path = str(path.relative_to(REPO_ROOT))
        text = path.read_text(encoding="utf-8", errors="ignore")

        for line_no, line in enumerate(text.splitlines(), start=1):
            for match in TRACKER_ID_PATTERN.finditer(line):
                tracker_id_failures.append(
                    f"{rel_path}:{line_no}: tracker ID '{match.group().strip()}'"
                )

    if failures or tracker_id_failures:
        if failures:
            print("FAIL (dead references):")
            for f in sorted(set(failures)):
                print(f"  - {f}")
            print(
                "\nIf this is a deliberate historical mention (e.g. \"moved from X\"), "
                "add (file, reference) to ALLOWLIST in tests/policy/doc_path_refs.py. "
                "Otherwise, point the reference at the file that owns the thing today."
            )
        if tracker_id_failures:
            print("FAIL (tracker IDs in reader-facing docs):")
            for f in sorted(set(tracker_id_failures)):
                print(f"  - {f}")
            print(
                "\nReader-facing docs should read standalone - drop the story/"
                "issue number, or move internal-only context to CLAUDE.md, "
                "docs/demo-runtime-evidence.md."
            )
        return 1

    print(
        f"PASS: {files_scanned} file(s) scanned for dead references, "
        f"{tracker_id_files_scanned} reader-facing doc(s) scanned for tracker IDs - none found."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
