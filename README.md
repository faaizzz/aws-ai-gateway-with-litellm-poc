# AWS AI Gateway with LiteLLM (PoC): self-service AI use-case onboarding

A product team onboards an AI use case by editing one YAML file and opening a PR. Terraform turns it into least-privilege IAM, an approved model route, a route-scoped gateway key, and budget and observability config.

**Terraform sets up the contract at plan time. The gateway and AWS enforce it at runtime.** Terraform is not a runtime policy engine.

> **Proof of concept.** A governed LLM gateway on AWS (LiteLLM on ECS Fargate, Amazon Bedrock in the EU, Langfuse Cloud traces) with Terraform-based, PR-driven onboarding of AI use cases. The organisation, teams and spend data are fictional. Sizing is for a demo, not production (see [Known limitations](#known-limitations)).

## Start here

| Topic | Where |
|---|---|
| Design: cost governance, platform contract, agentic safety, observability, model sourcing | [`design.md`](design.md) |
| Onboarding module, demonstrated on AdvisorChat | [`terraform/modules/use-case`](terraform/modules/use-case), [`usecases/`](usecases), [`tests/`](tests) (this README) |
| Target-state architecture | [`architecture.md`](architecture.md) |
| Model price/benchmark comparison | [`docs/model-analysis.md`](docs/model-analysis.md) |

The docs can also be built as an Antora site (`asci-doc/`, see [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md) for the optional CloudFront hosting).

![Target-state architecture overview](diagrams/architecture-overview.svg)

## Why

The synthetic sample in `data/sample_spend_30d.csv` shows a typical gap: $40,258.36 in 30 days, of which $2,418.97 (6.0%) has no team. The fix is a mandatory `team` and `use_case_id` that come from provisioned config, never from caller headers. [`tests/policy/spend_quality_checks.py`](tests/policy/spend_quality_checks.py) asserts the data problems (4 rows without a team, 1 without cost, 1 DigestBot row with cost but zero requests).

## The contract

`usecases/advisor-chat.yaml` is everything a team writes:

```yaml
metadata:
  id: advisor-chat
  owner: advisor-platform
  team: advisor
spec:
  dataClassification: confidential
  modelRoute: anthropic-claude-sonnet-bedrock
  budget:
    monthlyUsd: 10000    # ASSUMPTION, not an approved budget
  observability:
    tier: standard
```

This is a subset of the full contract in `design.md` (tool permissions, reliability and retention are not built). Teams never set provider, model IDs, IAM or gateway settings. Only [`terraform/catalog/approved-models.yaml`](terraform/catalog/approved-models.yaml) maps a route to a model:

| Route | Provider | Allowed classifications |
|---|---|---|
| `anthropic-claude-sonnet-bedrock` | Bedrock (EU profile) | internal, confidential |
| `anthropic-claude-haiku-bedrock` | Bedrock (EU profile) | public, internal, confidential |
| `external-llm-zdr` | External provider (ZDR) | public, internal |

## What the module does

[`terraform/modules/use-case`](terraform/modules/use-case) validates the declaration, resolves the route, and creates:

- IAM allowing only `bedrock:InvokeModel*` on the resolved model ARNs, on the gateway role (never `bedrock:*` or `*`)
- a route-scoped gateway key in Secrets Manager, so apps never hold AWS or provider credentials
- budget thresholds (75/90/100%) and observability config

**Rejected at `terraform plan`:** unknown route, `confidential` on `external-llm-zdr`, `restricted`, unknown classification or tier, budget of zero or less, missing owner or team, invalid id.

## Runtime vs Terraform guarantees

| Control | Terraform establishes | Runtime enforces |
|---|---|---|
| Use-case identity, owner, team | Yes | Attribution from the authenticated key |
| Approved provider and route | Yes | Rejects bypass and model override |
| IAM access | Yes | AWS |
| Budget | Thresholds and an AWS Budget alarm | Spend check and hard stop (`HTTP 422`) |
| Observability tier | Yes | Telemetry generation |
| Prompt/response handling | Configuration | Redaction and data handling |
| Audit trail | Resources and configuration | Request logging |

**Observability split:** Langfuse gets traces, including content where the classification allows. Datadog (target state) gets only derived metrics tagged `team`, `use_case_id`, `route`, `provider`, `environment`, never content.

## Run it

Offline, no credentials, from the repo root:

```bash
terraform fmt -check -recursive .
terraform init -test-directory=tests/terraform
terraform test -test-directory=tests/terraform        # 31 runs
for t in tests/policy/*.py; do python3 "$t"; done     # 3 scripts
```

Against the dev environment (needs AWS and Langfuse credentials, see [`terraform/environments/dev/README.md`](terraform/environments/dev/README.md)):

```bash
source .env.aws; source .env.langfuse
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev plan
```

CI runs fmt, validate, tests, policy tests, tflint, trivy and plan on every PR. Apply is a manual dispatch of a green plan run. See [`docs/ci.md`](docs/ci.md).

## Demo

Run against a real AWS account (`eu-central-1`); details in [`docs/demo-runtime-evidence.md`](docs/demo-runtime-evidence.md):

- model override attempt: denied (`HTTP 400`)
- unauthorised key: denied (`HTTP 401`)
- disallowed model for a valid key: denied (`HTTP 403`)
- allowed request: `HTTP 200` from Bedrock
- budget exhausted: `HTTP 422`

## Assumptions

- AdvisorChat's `monthlyUsd: 10000` is about 12% above the $8,915.04 in the sample data and is not an approved budget.
- The classification levels (`public/internal/confidential/restricted`) are this PoC's own. The sample traces' `pii_sensitive` maps to `confidential` and `no_pii` to `internal`.
- "EU" residency, not "Frankfurt only": Claude on Bedrock uses an `eu.*` inference profile.
- `external-llm-zdr` is not approved for `confidential`: ZDR covers retention, not the network boundary.
- LiteLLM on ECS Fargate is a PoC choice. Langfuse Cloud (EU) with synthetic prompts stands in for the self-hosted Langfuse.

## Known limitations

Demo trade-offs (public ALB with a WAF rate limit, self-signed certificate, default VPC, no RDS backups) are in [`docs/known-limitations.md`](docs/known-limitations.md). Also:

- Datadog is target state only. Nothing sends budget notifications or alerts today; the 100% hard stop works.
- Langfuse traces lack `use_case_id` and `route` (a LiteLLM OSS limitation).
- Not built: central identity, policy-as-code, multi-account deployment, DLP, failover, per-user quotas, MCP tool authorization.

## What I would add next

1. Stronger WAF: AWS managed rule groups and bot protection in front of the ALB.
2. Datadog: the LiteLLM metrics callback, dashboards, and budget and SLO alerts with notifications (`design.md` §1 and §5).
3. Tool permissions, reliability and retention in the contract.
4. A task role that alone can read the app's gateway key, with rotation and expiry.
5. Private network path to models: Bedrock VPC endpoint with an endpoint policy, `aws:SourceVpce` on the task role, internal ALB, private subnets, fixed-IP egress for the external provider.
6. SSO for employees: IdP groups mapped to gateway teams, default no access (`design.md` §2).
7. Allow several models per use case (today it is one).
8. Add an optional fallback model per use case.
9. CI/CD for QA and prod: one environment per stage with its own state and plan/apply roles, promoted by PR, and prod apply behind required reviewers (`docs/ci.md`).
10. Evals: a small test set per use case, run before any model change.
11. LiteLLM guardrails (prompt injection and PII checks) and retry and fallback settings.
12. Follow LiteLLM's [Rust migration](https://docs.litellm.ai/rust-migration) and test it before upgrading the pinned image.

## License

[MIT](LICENSE)
