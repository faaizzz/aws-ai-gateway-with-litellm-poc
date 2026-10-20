#!/usr/bin/env python3
"""Data-quality checks on data/sample_spend_30d.csv (synthetic sample data).

Standard-library only, by design: this is meant to run in CI with no
dependency install step. It does not modify the CSV; it asserts today's known
anomalies are still exactly what data/README.md documents, so a silent change
in the sample data (or a regression in a future ingestion pipeline modelled
on it) gets caught instead of ignored.

    python3 tests/policy/spend_quality_checks.py
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = REPO_ROOT / "data" / "sample_spend_30d.csv"

EXPECTED_UNATTRIBUTED_KEYS = {"key-research-shared", "key-personal-jdoe"}


def load_rows() -> list[dict[str, str]]:
    with CSV_PATH.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def check_missing_team_attribution(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Rows with no team must be rejected/quarantined by the spend pipeline,
    not silently aggregated as legitimate spend."""
    return [r for r in rows if not r["team"].strip()]


def check_missing_cost(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """A row with no cost_usd must be flagged for reconciliation, not treated
    as zero-cost."""
    return [r for r in rows if not r["cost_usd"].strip()]


def check_positive_cost_zero_requests(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Billed for zero requests is a signal of a billing/attribution bug, not
    normal usage - flag it rather than let it blend into team spend totals."""
    out = []
    for r in rows:
        cost = r["cost_usd"].strip()
        requests = r["request_count"].strip()
        if cost and requests and float(cost) > 0 and int(float(requests)) == 0:
            out.append(r)
    return out


def main() -> int:
    if not CSV_PATH.exists():
        print(f"FAIL: {CSV_PATH} not found .")
        return 1

    rows = load_rows()
    failures: list[str] = []

    unattributed = check_missing_team_attribution(rows)
    unattributed_keys = {r["api_key"] for r in unattributed}
    print(f"Missing team attribution: {len(unattributed)} row(s), keys={sorted(unattributed_keys)}")
    if len(unattributed) != 4:
        failures.append(f"expected 4 rows with missing team attribution, found {len(unattributed)}")
    if unattributed_keys != EXPECTED_UNATTRIBUTED_KEYS:
        failures.append(
            f"expected unattributed keys {sorted(EXPECTED_UNATTRIBUTED_KEYS)}, found {sorted(unattributed_keys)}"
        )

    missing_cost = check_missing_cost(rows)
    print(f"Missing cost_usd: {len(missing_cost)} row(s)")
    if len(missing_cost) != 1:
        failures.append(f"expected 1 row with missing cost_usd, found {len(missing_cost)}")

    zero_req_positive_cost = check_positive_cost_zero_requests(rows)
    print(f"Positive cost with zero requests: {len(zero_req_positive_cost)} row(s)")
    if len(zero_req_positive_cost) != 1:
        failures.append(
            f"expected 1 row with positive cost and zero requests, found {len(zero_req_positive_cost)}"
        )
    elif zero_req_positive_cost[0]["team"] != "DigestBot":
        failures.append("expected the positive-cost/zero-request row to belong to DigestBot")

    if failures:
        print("\nFAIL:")
        for f in failures:
            print(f"  - {f}")
        return 1

    print("\nPASS: sample_spend_30d.csv anomalies match the documented baseline.")
    print(
        "These are evidence for the platform contract, not something this script fixes: "
        "team/use_case_id must be mandatory and platform-owned so this class of row "
        "cannot occur for a use case onboarded through Terraform (see README.md)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
