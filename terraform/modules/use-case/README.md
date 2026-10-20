# `terraform/modules/use-case`

Turns one team's declaration (`usecases/<id>.yaml`) into least-privilege IAM, a gateway route, budget metadata and observability config. See the root `README.md` for the overall picture.

## Interface

```hcl
module "advisor_chat" {
  source = "../../modules/use-case"

  gateway_role_name = aws_iam_role.gateway_task_role.name
  gateway_role_arn  = aws_iam_role.gateway_task_role.arn

  use_case = {
    id                  = "advisor-chat"
    team                = "advisor"
    owner               = "advisor-platform"
    data_classification = "confidential"
    model_route         = "anthropic-claude-sonnet-bedrock"
    budget              = { monthly_usd = 10000 }
    observability       = { tier = "standard" }
  }
}
```

`gateway_role_*` is the one shared gateway task role. This module never creates it. It only attaches its own route-scoped policy to it. A smaller example is in [`examples/minimal`](examples/minimal).

`use_case` is a subset of the full contract in `design.md`. It has no tool permissions, reliability or retention fields yet.

## What it does

1. **Validates** every field: non-empty `id`/`team`/`owner`, `id` matches `^[a-z][a-z0-9-]{1,38}$`, classification is valid and not `restricted`, tier is `minimal` or `standard`, budget is above zero.
2. **Checks the catalogue:** the route must exist and be approved for the classification.
3. **Names resources** deterministically (`ai-usecase-<id>`, `ai-gateway-<id>`, `ai-budget-<id>`, `ai-observability-<id>`) and builds a platform-owned attribution map.
4. **Derives safe defaults** from the classification: trace retention, audit requirement, EU-only routing. Content never goes to Datadog.
5. **Creates IAM:** only `bedrock:InvokeModel` and `InvokeModelWithResponseStream`, on the resolved inference-profile ARN and its foundation-model ARNs. A non-Bedrock route gets no Bedrock grant.
6. **Emits config, not infrastructure:** route entry, budget thresholds (75/90/100%) and observability metrics. Terraform runs no budget engine or metrics pipeline.

The gateway master key, salt and Langfuse secret belong to `terraform/modules/llm-gateway`. The app's virtual key is minted in `terraform/environments/dev/virtual_key.tf`.

## Outputs

| Output | Contents |
|---|---|
| `resource_names` | The four deterministic names |
| `attribution` | Platform-owned attribution map |
| `resolved_route` | The catalogue entry the route resolved to |
| `safe_defaults` | Classification-derived defaults |
| `iam_policy_json` | The Bedrock policy (`null` for non-Bedrock routes) |
| `virtual_key_allowed_models` | Always `[route]`, never more |
| `budget_config` | Amount, thresholds, owner |
| `observability_config` | Tier, metrics, dimensions, content policy |

## Tests

Run from the **repo root**, because `-test-directory` cannot point above the configuration directory:

```bash
terraform init -test-directory=tests/terraform
terraform test -test-directory=tests/terraform
```

Tests for this module: `positive_contract`, `negative_contract` (11 failing cases), `iam_least_privilege` and `gateway_config`.

## Extending the contract

To add a field, keep the enforced value platform-owned. Do not let the team set it directly.

- **Tool permissions:** add a `tool_permissions` block to `use_case`, validate it, and output it for the gateway to enforce when it brokers a tool call.
- **Reliability** (`latency_sensitive` / `best_effort`): add it next to `observability.tier`. Use it for timeout and retry defaults and for page-vs-warn monitors.
- **Retention/audit:** turn `safe_defaults.trace_retention_days` and `audit_log_required` into team-overridable inputs, tightening only, once there is a Langfuse retention setting to wire them to.
