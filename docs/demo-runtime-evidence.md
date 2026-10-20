# Runtime demo evidence

Captured against the live deployment in a personal AWS account (`eu-central-1`): LiteLLM on ECS Fargate behind an ALB. This backs the "Demo" section of `README.md` with real commands and responses. Keys shown are masked or revoked.

```bash
GATEWAY_URL="https://<gateway-alb-dns-name>"   # terraform output, or the ALB in the console
APP_KEY=$(aws secretsmanager get-secret-value --secret-id ai-gateway-advisor-chat-app-key \
  --query SecretString --output text | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])")
```

## 1. Allowed request

```bash
curl -sk "$GATEWAY_URL/chat/completions" -H "Authorization: Bearer $APP_KEY" -H "Content-Type: application/json" \
  -d '{"model":"anthropic-claude-sonnet-bedrock","messages":[{"role":"user","content":"Reply with exactly: OK"}],"max_tokens":16}'
```

Result: `HTTP 200`, `"content":"OK"`, with `usage` token counts. The path is `curl -k` (self-signed certificate) → ALB → LiteLLM (authenticates the key) → `ai-gateway-task-role` → Bedrock `eu.anthropic.claude-sonnet-4-6` → Claude replies. It was repeated with the narrower IAM policy (only `aws-marketplace:ViewSubscriptions`) and still returned `HTTP 200`.

## 2. Denied requests

| Attempt | Result |
|---|---|
| Unknown key (`sk-not-a-real-key`) | `HTTP 401`, `token_not_found_in_db` |
| Valid key, model outside its route (`anthropic-claude-haiku-bedrock`) | `HTTP 403`, `key_model_access_denied` |
| Valid key, made-up model (`arbitrary-external-model`) | `HTTP 400`, invalid model name |

The `403` is the real route-scoping control. Haiku is a valid catalogue route, but this key's `allowed_models` does not include it.

## 3. Budget hard stop

A throwaway key was created with `max_budget: 0.0001`:

1. Request 1 succeeded (`HTTP 200`). Its real cost, $0.0001056, already exceeded the budget.
2. Request 2 was rejected: `HTTP 422`, `budget_exceeded` ("Current cost: 0.0001056, Max budget: 0.0001").

The key was then deleted. AdvisorChat's own key was untouched (`spend: 0.0`, `max_budget: 10000.0`, `models: ['anthropic-claude-sonnet-bedrock']`). Terraform only sets the budget when it mints the key. The spend check and the `422` are a LiteLLM and RDS runtime decision.

That key was later confirmed revoked (`/key/delete` returned `404 No keys found`, and using it returns `401`).

## 4. Per-use-case virtual key

`terraform apply` mints AdvisorChat's key through the live gateway's `/key/generate`. Its stored config matches the module outputs: `max_budget: 10000.0`, `models: ['anthropic-claude-sonnet-bedrock']`.

It is idempotent. A `plan` right after apply shows no changes. Re-running `terraform/environments/dev/scripts/ensure_virtual_key.sh` syncs through `/key/update`, creates no duplicate, and leaves the Secrets Manager value unchanged.

Platform-set attribution lives on the key's `metadata`: `use_case_id: advisor-chat`, `team: advisor`, `owner: advisor-platform`, `data_classification: confidential`, `route: anthropic-claude-sonnet-bedrock`, `provider: bedrock`. CloudWatch (`/ecs/ai-gateway-advisor-chat`) logs every attempt, denied or successful.

## 5. Langfuse traces

The gateway sends every call to a real Langfuse Cloud project (EU host, checked with `GET /api/public/traces`).

- **Present:** full input and output, provider-reported cost (e.g. `totalCost: 0.0002046`), tokens, latency, and `user_api_key_alias` (`ai-gateway-advisor-chat-app-key`, also the observation name) with the real budget (`10000`) and spend.
- **Absent:** `use_case_id`, `route`, `data_classification` and `owner`. LiteLLM's Langfuse callback forwards only its own fixed `user_api_key_*` fields, never a key's custom metadata. Putting `metadata` beside or inside `litellm_params`, or in `model_info`, changed nothing.
- **`null`:** `user_api_key_team_id` and `user_api_key_team_alias`. They need a LiteLLM `Team` object that this PoC does not create.

Not captured: a live `llm_cost_usd_total` point in Datadog, since the metrics callback is not wired. The metric shape and the no-content rule are checked in `tests/terraform/gateway_config.tftest.hcl`.

## 6. Problems found on the way

| Problem | Cause and fix |
|---|---|
| `AccessDeniedException` on `aws-marketplace:ViewSubscriptions` | Anthropic models are sold through AWS Marketplace, even via Bedrock. Accepted the agreement once with `aws bedrock create-foundation-model-agreement` and added a narrow `ViewSubscriptions` grant. (`Subscribe` was later removed, since only the one-time admin step needs it.) |
| `429 Too many tokens per day` | A new account's Anthropic quotas were `0`, below the stated default. `terraform/environments/dev/quotas.tf` requests the Haiku 4.5 quotas as code. They were approved in part: 10 requests/min, 5,000,000 tokens/min. |
| Sonnet "Legacy" access error | The pinned dated Sonnet snapshot had been retired by Bedrock. Repinned to the active `eu.anthropic.claude-sonnet-4-6` in `terraform/catalog/approved-models.yaml`. |
| `MalformedPolicyDocumentException` on `apply` | The CI role ARN variables defaulted to fake placeholder ARNs, which Secrets Manager rejects. They now default to `null` and are dropped with `compact()`. A real `apply` with no CI roles set is a clean no-op. |

The gateway log group's retention now follows the classification: 180 days for AdvisorChat (`aws logs describe-log-groups` shows `retentionInDays: 180`). The EU-only precondition is checked by the Terraform tests, since no real non-EU confidential route exists to test against.
