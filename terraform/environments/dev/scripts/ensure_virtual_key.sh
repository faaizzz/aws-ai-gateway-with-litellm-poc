#!/bin/bash
set -euo pipefail

# This script talks to LiteLLM's admin-only /key/list and /key/generate
# endpoints, both of which can return key/token-shaped fields in their
# response body.

# Idempotently ensure a route-scoped virtual key exists in LiteLLM's own
# Postgres-backed key table, and that its plaintext value is stored in Secrets
# Manager.

# Redacts and length-caps a LiteLLM API response body before it's safe to log.
redact_body() {
  python3 -c '
import json, re, sys
body = sys.stdin.read()
LIMIT = 300
SENSITIVE = re.compile(r"key|token|secret|password|credential", re.IGNORECASE)

def redact(obj):
    if isinstance(obj, dict):
        return {k: ("***REDACTED***" if SENSITIVE.search(k) else redact(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [redact(v) for v in obj]
    return obj

try:
    out = json.dumps(redact(json.loads(body)))
except (json.JSONDecodeError, ValueError):
    out = body
print(out[:LIMIT] + ("...(truncated)" if len(out) > LIMIT else ""))
' <<<"$1" 2>/dev/null || printf '%.300s...(truncated, redaction step failed)\n' "$1"
}

: "${GATEWAY_URL:?GATEWAY_URL is required}"
: "${MASTER_KEY_SECRET_ARN:?MASTER_KEY_SECRET_ARN is required}"
: "${KEY_ALIAS:?KEY_ALIAS is required}"
: "${MODELS_JSON:?MODELS_JSON is required}"
: "${MAX_BUDGET:?MAX_BUDGET is required}"
: "${SOFT_BUDGET:?SOFT_BUDGET is required}"
: "${METADATA_JSON:?METADATA_JSON is required}"
: "${TARGET_SECRET_ID:?TARGET_SECRET_ID is required}"
: "${USE_CASE_ID:?USE_CASE_ID is required}"
: "${ROUTE:?ROUTE is required}"

echo "[ensure_virtual_key] resolving platform master key from Secrets Manager..."
MASTER_KEY=$(aws secretsmanager get-secret-value --secret-id "$MASTER_KEY_SECRET_ARN" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')

# The gateway may still be mid-rollout right after apply - retry briefly
# rather than failing the whole apply on a transient connection refusal.
ATTEMPTS=0
MAX_ATTEMPTS=12
until LIST_RESPONSE=$(curl -sk -f -H "Authorization: Bearer $MASTER_KEY" \
  "$GATEWAY_URL/key/list?key_alias=$KEY_ALIAS" 2>/dev/null); do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
    echo "ERROR: gateway at $GATEWAY_URL did not become reachable after $MAX_ATTEMPTS attempts." >&2
    exit 1
  fi
  echo "[ensure_virtual_key] gateway not reachable yet (attempt $ATTEMPTS/$MAX_ATTEMPTS) - retrying in 5s..."
  sleep 5
done

# A malformed/empty body or a missing/non-numeric `total_count` field must
# fail loudly, never silently default to 0.
if ! TOTAL_COUNT=$(echo "$LIST_RESPONSE" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(int(d["total_count"]))
'); then
  # Curl's `-f` above already guarantees this branch is only reached on a
  # 2xx response - so "status" here is necessarily "200-series, but unusable
  # body".
  echo "ERROR: /key/list returned a 2xx response that could not be parsed as JSON with a numeric total_count field. Refusing to guess - failing rather than risking a duplicate key. Redacted response body: $(redact_body "$LIST_RESPONSE")" >&2
  exit 1
fi

REQUEST_BODY=$(python3 -c 'import json,sys
key_alias, models_json, max_budget, soft_budget, metadata_json = sys.argv[1:6]
print(json.dumps({
    "key_alias": key_alias,
    "models": json.loads(models_json),
    "max_budget": float(max_budget),
    "soft_budget": float(soft_budget),
    "budget_duration": "30d",
    "metadata": json.loads(metadata_json),
}))
' "$KEY_ALIAS" "$MODELS_JSON" "$MAX_BUDGET" "$SOFT_BUDGET" "$METADATA_JSON")

if [ "$TOTAL_COUNT" -gt 0 ]; then
  echo "[ensure_virtual_key] alias '$KEY_ALIAS' already exists (total_count=$TOTAL_COUNT) - syncing via /key/update, never /key/generate."
  curl -sk -f -X POST "$GATEWAY_URL/key/update" \
    -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" > /dev/null
  echo "[ensure_virtual_key] synced existing key. Secrets Manager entry left untouched (plaintext value only exists at generation time)."
  exit 0
fi

echo "[ensure_virtual_key] no existing key for alias '$KEY_ALIAS' - generating one."
GENERATE_RESPONSE=$(curl -sk -f -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")

NEW_KEY=$(echo "$GENERATE_RESPONSE" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(d.get("key") or "")
')

if [ -z "$NEW_KEY" ]; then
  # Same reasoning as the /key/list branch above - curl's `-f` means this
  # only fires on a 2xx /key/generate response whose body just didn't carry
  # a `key` field.
  echo "ERROR: /key/generate returned a 2xx response with no key field. Redacted response body: $(redact_body "$GENERATE_RESPONSE")" >&2
  exit 1
fi

# Never let the plaintext key land in a subprocess's argv.
SECRET_JSON=$(USE_CASE_ID="$USE_CASE_ID" ROUTE="$ROUTE" KEY_ALIAS="$KEY_ALIAS" NEW_KEY="$NEW_KEY" python3 -c '
import json, os
print(json.dumps({
    "use_case_id": os.environ["USE_CASE_ID"],
    "route": os.environ["ROUTE"],
    "key_alias": os.environ["KEY_ALIAS"],
    "key": os.environ["NEW_KEY"],
}))
')

# `file:///dev/stdin` is the AWS CLI's documented file:// parameter-loading
# convention applied to stdin.
printf '%s' "$SECRET_JSON" | aws secretsmanager put-secret-value \
  --secret-id "$TARGET_SECRET_ID" --secret-string file:///dev/stdin > /dev/null

echo "[ensure_virtual_key] stored new virtual key (alias '$KEY_ALIAS') in Secrets Manager secret $TARGET_SECRET_ID."
