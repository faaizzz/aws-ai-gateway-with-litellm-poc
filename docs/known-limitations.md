# Known limitations and production considerations

These are PoC trade-offs. None is a gap in the contract itself.

## Demo trade-offs

- **Public ALB with a burst limiter only.** A WAF rule limits each client IP to 50 requests per 10 minutes (1,000 for trusted IPs), set in `terraform/catalog/gateway-waf.yaml`. It is a burst limit, not a daily quota, and there are no managed rule groups.
- **ALB access logs keep client IPs for 90 days** (`alb_log_retention_days`, an assumption pending DPO input) in an SSE-S3 bucket. They are the only record of requests the WAF blocks, which never reach LiteLLM or Langfuse.
- **Broad task egress, no NAT or VPC endpoints.** The task needs several internet services with no stable CIDR. The ALB and RDS egress rules are scoped.
- **AWS-managed keys, no customer-managed KMS.** Too much for a demo with no cross-account access.
- **Default VPC, no RDS backups, no deletion protection.** A `destroy` discards the data anyway (`skip_final_snapshot = true`).
- **Self-signed ALB certificate.** Requests need `curl -k`. Production would use a DNS-validated ACM certificate.
- **The saved plan artifact holds low-risk values** (ARNs, names), but never key material. The gateway keys are write-only, and CI asserts this every run with `scripts/ci/check_no_secret_material_in_plan.sh`. The artifact is kept 1 day.
- **Log retention follows classification:** 180 days for `confidential`, 60 for `internal`, 30 otherwise. At scale, six months of logs is a real cost to weigh against the audit need.
- **Datadog is not deployed.** `design.md` and the diagram keep it as target state.
- **No budget notifications.** The hard stop at 100% (`max_budget`) works, and keys carry a `soft_budget` (75%), but nothing sends a warning. The 75%/90% notifications, paging and SLO alerts are Datadog target state (`design.md`). The AWS Budget alarm publishes to an SNS topic with no subscriber.
- **Langfuse traces lack `use_case_id`, `route` and `data_classification`,** and `team_id` and `team_alias` are `null`. Content, cost, tokens, latency, key alias and budget are real. See `docs/demo-runtime-evidence.md`.
- **No ECR repo.** The task pulls LiteLLM from `ghcr.io`.
- **RDS master-password rotation breaks the running gateway.** The password is AWS-managed and rotates (observed 2026-09-30); the task reads `DB_PASSWORD` only at start, so the UI's virtual keys, teams and spend logging fail with 503 until redeployed. The `ai-gateway-advisor-chat-db-reconnect-failed` alarm fires (console only, no notification topic). Fix: `aws ecs update-service --cluster <cluster> --service ai-gateway-advisor-chat --force-new-deployment`. Next scheduled rotation: 2026-10-08.
- **The pinned LiteLLM tag (`v1.102.1`) is committed but not yet redeployed** to the live task.

## Production considerations

Out of scope here:

- **Dependency updates:** Dependabot runs weekly, grouped, at most 3 open PRs. Nothing auto-merges. Each PR must pass the `terraform.yml` gate.
- **Apply approval inside the pipeline:** move apply into `terraform.yml` behind a `dev-apply` environment with required reviewers, replacing the separate `terraform-apply.yml`. See [`ci.md`](ci.md#future-environment-with-required-reviewers-out-of-scope). Not available on this repo's GitHub plan.
- **One Terraform state.** It holds the gateway and every use case, so an onboarding PR plans the whole platform. Splitting it is a production step.
- **Private network path to models:** Bedrock is reached over the internet from a public-IP task. Target: `bedrock-runtime` VPC endpoint with an endpoint policy, `aws:SourceVpce` on the task role, internal ALB, private subnets, and controlled fixed-IP egress for the external provider. See "What I would add next" in the README.
- Central identity and authorization (the demo's gateway auth is a stand-in).
- Policy-as-code and automated approvals for sensitive classifications.
- Multi-account deployment, separate accounts per environment, centralized audit storage.
- Downgrade instead of blocking at the hard stop (needs a fallback-route field, see `design.md`).
- DLP and redaction, provider failover, rate limits, per-user quotas.
- MCP and tool authorization (designed in `design.md`, not built).
- Formal SLO management.
