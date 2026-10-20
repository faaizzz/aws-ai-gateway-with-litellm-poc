# `terraform/modules/llm-gateway`

The shared LiteLLM gateway: ALB, ECS Fargate, RDS Postgres, security groups, IAM roles, WAF, and the master key, salt and Langfuse secrets. It is one per gateway and does not depend on any use case.

LiteLLM is a PoC choice, not a requirement of the design. Terraform generates the gateway config (`locals.tf`) and deploys it (`ecs.tf`), so it cannot drift from what `terraform plan` validated. See the root `README.md` and `terraform/modules/use-case/README.md`.

## Files

| File | Contents |
|---|---|
| `variables.tf` | Networking, certificate, image, catalogue path, log retention, Langfuse keys, CI/operator ARNs |
| `locals.tf` | Loads the catalogue and builds the LiteLLM `model_list` |
| `iam.tf` | Task role, execution role, secrets policy |
| `security_groups.tf` | ALB, task and RDS security groups |
| `alb.tf` | ALB, target group, HTTPS listener, access logging |
| `alb_logs.tf` | S3 bucket for ALB access logs (client IPs), expires after `alb_log_retention_days` |
| `waf.tf` | WAF per-IP rate limit on the ALB, driven by `terraform/catalog/gateway-waf.yaml` |
| `ecs.tf` | Cluster, log group, task definition, service |
| `rds.tf` | Subnet group and Postgres instance |
| `secrets.tf` | Master key, salt and Langfuse secrets, and their policies |
| `outputs.tf` | What the use-case module and environment root consume |

## Why a separate module

The master and salt keys used to live in the use-case module, so each new use case would have created another unused pair. Now they are created once here.

## The catalogue drives `model_list`

`model_list` has one entry per **Bedrock** route in `terraform/catalog/approved-models.yaml`, whether or not a use case declares it. Per-use-case limits come from elsewhere:

- **Which models a caller may use:** the virtual key's `models` list, always only that use case's route.
- **Which ARNs the gateway may invoke:** the union of the policies each use-case module attaches to this module's task role.

So a catalogue route with no use case is in `model_list` but denied by IAM.

The generated config looks like this (one entry per Bedrock route):

```yaml
model_list:
  - model_name: anthropic-claude-sonnet-bedrock
    litellm_params:
      model: bedrock/eu.anthropic.claude-sonnet-4-6
      aws_region_name: eu-central-1
  - model_name: anthropic-claude-haiku-bedrock
    litellm_params:
      model: bedrock/eu.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: eu-central-1
litellm_settings:
  success_callback: [langfuse]
  failure_callback: [langfuse]
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

**Limitation:** `external-llm-zdr` is not in `model_list`, because no credential for it is wired. Adding it needs a Secrets Manager secret for the API key, an execution-role grant, and a `model_list` entry using `api_key: os.environ/...`.

## Authentication

- **Master key** (`LITELLM_MASTER_KEY`, from Secrets Manager): authenticates the LiteLLM process and Terraform's key-management calls. It is never given to an application.
- **Virtual key per use case:** the application's real credential. It is minted from the master key with only that use case's route, plus its budget and attribution metadata. It is stored in Secrets Manager. See `terraform/environments/dev/virtual_key.tf`.

## Attribution

Attribution is set on the virtual key's `metadata` by the platform. Callers cannot set or override it.

## Budget alerts

None are sent today. The gateway enforces the hard stop (`max_budget`, `HTTP 422`), and each key carries a `soft_budget` (75% of `monthly_usd`) set by `terraform/environments/dev/virtual_key.tf`. Warnings and notifications are Datadog target state (`design.md` §1 and §5).

## Langfuse traces

Every call, successful or failed, is traced to Langfuse Cloud (EU). Credentials are in `.env.langfuse` (see `CLAUDE.md`).

- **Works:** full input and output, real cost, tokens, latency, and the key alias and budget.
- **Gap:** `use_case_id`, `route` and `data_classification` do **not** appear on traces. LiteLLM's Langfuse callback only forwards its own `user_api_key_*` fields, not a key's custom metadata.
- **Gap:** `team_id` and `team_alias` are `null`. They need a LiteLLM `Team` object that this PoC does not create.

Details and captured output are in `docs/demo-runtime-evidence.md`.

## Gateway key rotation

The master key and the salt are generated as `ephemeral "random_password"` and written to Secrets Manager with write-only `secret_string_wo`. They never appear in state or in a saved plan. CI checks this with `scripts/ci/check_no_secret_material_in_plan.sh`.

**Two secrets, not one.** Without a separate `LITELLM_SALT_KEY`, LiteLLM encrypts its stored virtual keys with the master key. Rotating the master key would then break every stored key. The salt is generated once and never bumped.

**Rotation is deliberate.** A secret is rewritten only when its `secret_string_wo_version` changes, so an unrelated `apply` never rotates a key.

**Master-key rotation runbook**

1. Confirm the salt secret is already applied and wired into the running task.
2. Bump `secret_string_wo_version` on `aws_secretsmanager_secret_version.gateway_key` and apply.
3. Force a new ECS deployment: `aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment`. ECS does not restart a task when a secret's value changes.
4. Re-run `terraform/environments/dev/scripts/ensure_virtual_key.sh` and confirm each use case's key still works end to end.

**Never bump the salt's version** after its first apply. It would orphan every stored virtual key.

## Edge protection: WAF and ALB logs

LiteLLM only sees the ALB's private address, so the ALB writes access logs to S3 to keep the real client IP, including for requests the WAF blocks. A WAF rate rule limits each IP per 10 minutes; `trustedCidrs` get a higher limit. Both are set in `terraform/catalog/gateway-waf.yaml`. WAF windows max out at 10 minutes, so this is a burst limit, not a daily quota (use LiteLLM per-key limits for that).

## Extending

Another environment means instantiating the module again with its own VPC, subnets and certificate (the `ai-gateway-*` names are hardcoded). A gateway per use case is out of scope.

## Not built

- A per-use-case application role that alone reads its key secret.
- Recovery if a key's secret is lost (today: delete the key in LiteLLM and re-apply).
- JWT/OIDC validation of the calling app, on top of its virtual key.
