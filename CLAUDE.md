# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A proof of concept for a governed LLM gateway on AWS with Terraform-based, PR-driven use-case onboarding. The organisation, teams and data are fictional. Where something is unspecified, make a reasonable assumption and state it.

## Scope

- `design.md`: cost governance; the platform contract (owner, classification, approved models *and providers*, tool permissions, budget, reliability, retention/audit) and its lifecycle (validate, approve, change, retire); applying it to AdvisorChat, KYC and DevAgent; agentic/MCP tool safety; observability; model sourcing with the math; six-month direction.
- Self-service use-case onboarding via Terraform, demonstrated on **AdvisorChat**: the module, tests and `README.md` (includes "Runtime vs Terraform guarantees" and "What I would add next").
- A **target-state** architecture diagram (`diagrams/`): the gateway, both providers, Langfuse traces vs Datadog derived metrics, audit/trace paths incl. Postgres request logs, and where the onboarding module sits.

A DPO/Legal reader must be able to answer: where can a product's data go, what do we log and for how long, and how would we reconstruct a past interaction. Prefer small and complete over large and half done. Don't add EKS, NAT Gateway, multi-region, a control-plane service, a UI, a policy engine or a self-hosted Langfuse.

## Repo layout

- `usecases/*.yaml` — product-team declarations (`advisor-chat`, `digestbot`)
- `terraform/catalog/approved-models.yaml` — platform-owned route catalogue; `gateway-waf.yaml` — ALB WAF rate limits and trusted CIDRs
- `terraform/modules/use-case` — the use-case onboarding module; `llm-gateway` — shared LiteLLM/ECS/ALB/RDS stack; `use-case-observability` — per-use-case AWS Budget alarm
- `terraform/environments/dev` — wiring-only root; `terraform/bootstrap` — state bucket + GitHub OIDC roles (applied once locally)
- `tests/terraform`, `tests/policy` — see Commands
- `design.md`, `architecture.md`, `diagrams/` (`*.mmd` → `*.svg`, render with `scripts/render-diagrams.sh`) — design and architecture
- `docs/` — CI notes, known limitations, dated demo evidence log
- `.claude/skills/` — repo workflows (verify, onboard a use case, render diagrams, docs site, rotate a secret, apply a plan)
- `asci-doc/` — Antora docs site (Markdown → AsciiDoc at build time); published by the manual `docs-publish.yml` to S3 + CloudFront (hosting in `terraform/bootstrap`)
- `data/` — synthetic sample data (see below)

## Sample data (synthetic)

`data/sample_spend_30d.csv` and `data/sample_traces.json` are synthetic; totals and the deliberate anomalies are listed in `data/README.md` and asserted by `tests/policy/spend_quality_checks.py`. They justify mandatory `team`/`use_case_id`, platform-owned attribution and spend data-quality checks. Use model-spend figures to justify logical routes, not to prescribe a model. The traces use `data_class` `pii_sensitive`/`no_pii` (mapped to `confidential`/`internal`), attribute only via `team`/`product`/`litellm_proxy_key_alias` (no `use_case_id`), and include a Bedrock throttle and cache-read tokens (why cost should come from provider/gateway-reported cost).

## AWS access

- Region `eu-central-1` (Frankfurt). Keep your profile/region in `.env.aws` (gitignored; copy `.env.aws.example`) and `source .env.aws` before any `aws`/`terraform` command.
- The state bucket name `ai-gateway-tfstate-123456789012` in the `backend.tf` files and `terraform/bootstrap` is a placeholder; replace it with your own.
- **GitHub Actions:** no local profile. Set `AWS_REGION: eu-central-1` and use `aws-actions/configure-aws-credentials` with OIDC role assumption, no long-lived keys. The provider and the `github-actions-plan`/`github-actions-apply` roles come from `terraform/bootstrap/` (applied once locally); their ARNs are the `AWS_PLAN_ROLE_ARN`/`AWS_APPLY_ROLE_ARN` repo **secrets**.

## Datadog and budget alerts

- Datadog is **not deployed**; it is target state only (`design.md` and the diagram), including budget notifications, SLO alerts and paging. Nothing sends alerts today.
- Keys keep `soft_budget` (75% of `monthlyUsd`); the 100% hard stop (`max_budget`, `HTTP 422`) works.

## Target state that is documented, not built

These are in `design.md`, the diagrams and the README's "What I would add next", and should not be implemented unless asked: Bedrock VPC endpoint (PrivateLink) with internal ALB and fixed-IP egress, SSO with IdP-group-to-team mapping, an AdvisorChat task role that alone reads the app key, Datadog, the tool/MCP broker, self-hosted Langfuse.

## Langfuse access

- `terraform/modules/llm-gateway/secrets.tf` wires the gateway's `success_callback`/`failure_callback` to a real Langfuse Cloud project. Credentials live in `.env.langfuse` (gitignored, never committed): `LANGFUSE_PUBLIC_KEY` (`pk-lf-...`), `LANGFUSE_SECRET_KEY` (`sk-lf-...`), `LANGFUSE_HOST`.
- **Region hosts:** EU is `https://cloud.langfuse.com`, US is `https://us.cloud.langfuse.com` (`eu.cloud.langfuse.com` does not exist). Verified against Langfuse's docs and live credentials. The deployment is pinned to the EU host; `langfuse_host` has a `validation` block rejecting anything else (`terraform/environments/dev/variables.tf`).
- **These need to reach the running container**, not just Terraform itself — Terraform variables (`ephemeral = true`), not provider-level env-var auto-detection. Map the names before running `terraform plan`/`apply` on `terraform/environments/dev`:

  ```bash
  source .env.langfuse
  export TF_VAR_langfuse_public_key="$LANGFUSE_PUBLIC_KEY"
  export TF_VAR_langfuse_secret_key="$LANGFUSE_SECRET_KEY"
  export TF_VAR_langfuse_host="$LANGFUSE_HOST"
  ```

- Verify a key pair actually works before assuming a Terraform/LiteLLM failure is this repo's bug: `curl -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$LANGFUSE_HOST/api/public/projects"` should return your project(s), not a 401/403.
- Keys are stored in Secrets Manager via write-only `secret_string_wo`/`secret_string_wo_version` (the `TF_VAR_langfuse_*` variables are `ephemeral`, so they never reach state or a saved plan) and injected into the ECS task as `secrets`, never as plaintext env values. This is why root `required_version` is `>= 1.11.0`.
- **Rotating a Langfuse key**: get the new key from the Langfuse Cloud project settings, `source .env.langfuse` with the updated value (and update `.env.langfuse` itself), bump `secret_string_wo_version` on `module.llm_gateway.aws_secretsmanager_secret_version.langfuse_keys` in `terraform/modules/llm-gateway/secrets.tf`, then `apply`. Force a new ECS deployment afterwards (`aws ecs update-service --force-new-deployment`) — same as the gateway-key runbook in `terraform/modules/llm-gateway/README.md` — since ECS does not restart a running task just because the underlying Secrets Manager value changed.

## Commands

```bash
# Format / validate / plan the dev environment
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan

# Native Terraform tests for the module (the contract's positive and negative cases).
# Run from the REPO ROOT, not from terraform/modules/use-case — see note below.
terraform init -test-directory=tests/terraform
terraform test -test-directory=tests/terraform
terraform test -test-directory=tests/terraform -filter=tests/terraform/<file>.tftest.hcl   # single file
```

**Tests run from the repo root**, not from the module: `-test-directory` must be a subdirectory of the configuration in use, so `../..` is rejected.

- The root is an intentionally empty Terraform configuration (only `versions.tf`); `init` and `test` both need `-test-directory=tests/terraform`.
- Each `run` block carries its own `module { source = "./terraform/modules/..." }` (relative to the repo root).
- Commit the root `.terraform.lock.hcl`; it pins the provider versions the tests use.
- Tests need no AWS credentials: a real `provider "aws"` block with fake static keys and all `skip_*` flags, plus `override_data` for `data.aws_caller_identity.current`. We do not use a project-wide `mock_provider "aws"`, because it also mocks `aws_iam_policy_document`, whose real output the tests assert on. All runs use `command = plan`.

Policy and data-quality tests live under `tests/policy/` and run with plain `python3` (stdlib only, no install step):

```bash
python3 tests/policy/spend_quality_checks.py   # the spend-CSV anomalies (see "Supplied data")
python3 tests/policy/usecase_schema_checks.py  # usecases/*.yaml shape, independent of Terraform
python3 tests/policy/doc_path_refs.py          # no dead file path or bare *.tf mention anywhere in the docs
```

## Architecture in brief

The onboarding flow crosses several files:

1. `usecases/<id>.yaml` is the product team's entire contract: id, team, owner, classification, logical route, budget and observability tier. This is a deliberate subset of the full contract that `design.md` defines; tool permissions, reliability and retention/audit live there.
2. `terraform/environments/dev/main.tf` reads it with `yamldecode(file(...))` and passes it to `terraform/modules/use-case` as a single typed `use_case` object.
3. The module resolves `model_route` against the platform-owned `terraform/catalog/approved-models.yaml` and checks the route's `allowed_classifications`. Invalid combinations must fail at plan time. Cross-field checks against the catalogue use Terraform ≥ 1.9 variable validation (which may reference other module objects) or `lifecycle` preconditions. A missing object field fails type conversion, but an empty string does not — so `id`, `team` and `owner` also need non-empty checks.
4. The module then emits:
   - the IAM policy, scoped to the resolved Bedrock model ARN(s)
   - the LiteLLM route/key config, carrying platform-owned attribution metadata
   - budget thresholds and alarms (75%, 90% and 100%)
   - the observability config
   - classification-derived safe defaults
5. At runtime, the gateway (LiteLLM on ECS Fargate, a PoC choice) enforces the configuration: auth, route pinning and spend checks. Terraform does not enforce anything at runtime.

Providers are Bedrock Frankfurt (Anthropic models) and an External LLM Provider reached via direct API under ZDR. The catalogue should model both, with the external route not approved for `confidential`.

Observability split: raw prompts and responses may reach Langfuse/traces only. Datadog gets only derived metrics tagged with `team`, `use_case_id`, `route`, `provider` and `environment`.

## Invariants that are easy to break while editing

- Product teams never set provider or model IDs, IAM, LiteLLM settings or AWS details. Only the catalogue maps a logical route to a concrete model.
- IAM grants only `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on specific model resources, granted to the gateway task role only; applications receive only a route-scoped gateway key. Never use `bedrock:*` or `*`.
- `restricted` classification is denied by default. `confidential` resolves only to routes explicitly approved for it.
- Credentials never appear in source, YAML or Terraform outputs. Bedrock uses IAM; the external provider key goes in Secrets Manager and is readable only by the gateway role.
- Attribution fields come from the provisioned config and the authenticated identity, never from caller-supplied headers.
- The AdvisorChat `monthlyUsd: 10000` is an implementation assumption (about 12% above the $8,915.04 in the sample data). Label it as an assumption everywhere.
- The classification taxonomy (`public/internal/confidential/restricted`) is our assumption. The sample traces use `pii_sensitive`/`no_pii`, so document the mapping.
- Safe defaults are derived from classification, never set by the team (e.g. `confidential` → EU Bedrock only, no content to Datadog, stricter retention/audit).
- Bedrock Anthropic models are invoked via an `eu.` cross-region inference profile, so IAM must allow the profile ARN plus the foundation-model ARNs in each EU region it routes to. Data stays in the EU, not strictly Frankfurt — state this as a residency assumption.
- Use-case IDs: lowercase letters, digits, hyphens, start with a letter, bounded length; immutable (a new identity means a new declaration). Resource names are deterministic: `ai-<kind>-<id>`.
- Budget thresholds are 75% / 90% (warn) and 100% (enforcement action). Terraform establishes budget, thresholds, attribution and alarms; the runtime does spend checks and block/downgrade decisions. Terraform is not a runtime policy engine.
- Observability tiers are `minimal` and `standard`. Datadog metrics (`llm_requests_total`, `llm_request_errors_total`, `llm_provider_throttles_total`, `llm_input_tokens_total`, `llm_output_tokens_total`, `llm_cost_usd_total`, `llm_request_duration_seconds`) carry no high-cardinality dimensions (user/customer ID, prompt, response, document contents).
- Demo sizing: ECS Fargate 1 task, 0.5 vCPU / 2 GB (1 GB was OOM-killed under admin-UI load); RDS `db.t4g.micro`, 20 GB, single-AZ, private; short log retention. No NAT Gateway (public subnets + security groups). State lives in S3 with `use_lockfile = true`. Never commit state, `*.tfvars` or credentials.
- CI runs fmt, validate, test, policy tests, tflint and trivy, then plan on PRs, using a read-only plan role. Apply is only a manual dispatch of `terraform-apply.yml` with a green `terraform.yml` run's ID on `main`, using the separate apply role. Docs publish (`docs-publish.yml`) is manual and `main` only.
- The gateway's ALB is public behind a WAF per-IP rate limit; ALB access logs (client IPs, 90 days) go to S3. Both are documented limitations, not target state.
