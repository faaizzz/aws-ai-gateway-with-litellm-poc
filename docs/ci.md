# CI/CD detail

Workflows are in `.github/workflows/`.

## `terraform.yml` (pull requests and `main`)

1. **`fmt`, `validate`, `test`, `policy-tests`, `tflint`, `trivy`** run with no AWS credentials. `trivy` fails on any HIGH or CRITICAL finding. Accepted PoC deviations (see [`known-limitations.md`](known-limitations.md)) are silenced inline with `# trivy:ignore:<ID>` and a reason.
2. **`plan`** runs after those, using the read-only OIDC role `AWS_PLAN_ROLE_ARN`. It saves `tfplan` as the `tfplan-dev` artifact, kept 1 day. A missing secret fails the job.

## The apply gate

Apply is a separate workflow, `terraform-apply.yml`. It has only a manual `workflow_dispatch` trigger with a `plan_run_id` input, and never runs after `plan` or on a push. GitHub's required-reviewers protection is not available on this repo's plan, so the review step is manual:

1. A human reads a green `plan` run.
2. They dispatch `terraform-apply.yml` with that run's ID.
3. It checks the run is a successful `terraform.yml` run on `main`, downloads that run's `tfplan-dev`, and applies that exact plan. A stale plan is refused by Terraform.

Set this gate up before putting real role ARNs in the secrets.

### Future: required reviewers (out of scope)

Better is an `apply` job in `terraform.yml` behind a `dev-apply` environment with required reviewers, so approval covers the exact plan and no run ID is copied. The apply role already trusts that environment. It is not available on this repo's GitHub plan, and an unreviewed in-workflow apply would be weaker than this two-step gate.

## CI credentials (OIDC)

`terraform/bootstrap/` creates the GitHub OIDC provider and two roles. Apply it once, locally. No long-lived AWS keys are stored in GitHub.

```bash
source .env.aws
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
gh secret set AWS_PLAN_ROLE_ARN  --body "$(terraform -chdir=terraform/bootstrap output -raw plan_role_arn)"
gh secret set AWS_APPLY_ROLE_ARN --body "$(terraform -chdir=terraform/bootstrap output -raw apply_role_arn)"
```

| Role | Trusted for | Permissions |
|---|---|---|
| `github-actions-plan` | any ref of this repo | Read-only on the managed services, state read, write only on lock files |
| `github-actions-apply` | `main` (or the `dev-apply` environment) | Plan's reads plus create/update/delete; IAM and Secrets limited to `ai-*` names |

If the account already has a GitHub OIDC provider, pass `-var create_oidc_provider=false`.

## `docs-publish.yml` (manual)

Builds the Antora site in `asci-doc/` and publishes it to S3/CloudFront. It runs only on `workflow_dispatch`; there is no push or PR trigger.

- **Input `publish`** (boolean, default `true`): `false` builds and uploads the `docs-site` artifact only. `true` also syncs the site to the docs bucket (`--delete` removes pages deleted from the source) and invalidates the CloudFront cache.
- **Publishing needs `main`.** With `publish=true` on another ref the build job fails with an error before doing anything, and the `github-actions-docs` role trusts `refs/heads/main` only, so it could not be assumed anyway.
- **Role:** `github-actions-docs`, created by `terraform/bootstrap/`. It can list and write the docs bucket and create invalidations on that one distribution, nothing else.
- **Settings:** the secret and variables below. The build job fails with a clear error if one is missing when `publish=true`.
- Site build details: `asci-doc/README.md`.

## Drift and idempotency

Both use `terraform plan -detailed-exitcode`. Nothing runs `apply -auto-approve` on a schedule.

- **Post-apply check:** `terraform-apply.yml` re-plans after applying and fails on any diff.
- **Daily drift detection:** `drift-detection.yml` re-plans with the read-only role and fails on drift. The failed run is the notification.

## Required secrets and variables

| Name | Kind | Notes |
|---|---|---|
| `AWS_PLAN_ENABLED` | variable | Set to `true` to run the `plan` and drift-detection jobs. Without it (e.g. in a fresh fork) they are skipped and only the offline checks run. |
| `AWS_PLAN_ROLE_ARN` | secret | Read-only plan role. Also passed as `TF_VAR_ci_plan_role_arn`. |
| `AWS_APPLY_ROLE_ARN` | secret | Apply role, trusted for `main` only. Also passed as `TF_VAR_ci_apply_role_arn`. |
| `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY` | secret | Langfuse Cloud keys, mapped to `TF_VAR_langfuse_*`. |
| `LANGFUSE_HOST` | variable | Must be `https://cloud.langfuse.com` (EU only). |
| `AWS_DOCS_ROLE_ARN` | secret | `github-actions-docs` role, used by `docs-publish.yml` only. |
| `DOCS_BUCKET`, `DOCS_DISTRIBUTION_ID`, `DOCS_SITE_URL` | variable | Docs bucket name, CloudFront distribution ID and site URL, from the `terraform/bootstrap` outputs. |
