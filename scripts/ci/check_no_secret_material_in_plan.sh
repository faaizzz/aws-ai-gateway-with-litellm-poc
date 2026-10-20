#!/usr/bin/env bash
# Acceptance: `terraform show -json` of a saved plan must never contain
# gateway/salt key material.
set -euo pipefail

PLAN_JSON="${1:?usage: check_no_secret_material_in_plan.sh <plan-or-state.json>}"

violations=$(jq -r '
  [.. | objects | select(.type? == "aws_secretsmanager_secret_version")]
  | map(select(
      (.values.secret_string_wo // "") != "" or
      (.values.secret_string // "") != "" or
      (.values.secret_binary // "") != ""
    ))
  | map(.address // .name // "unknown")
  | .[]
' "$PLAN_JSON")

if [ -n "$violations" ]; then
  echo "Secret material found in $PLAN_JSON for:" >&2
  echo "$violations" >&2
  exit 1
fi

echo "OK: no aws_secretsmanager_secret_version in $PLAN_JSON carries a non-empty secret_string/secret_string_wo/secret_binary."
