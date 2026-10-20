---
name: tf-verify
description: Run the full local verification for Terraform changes in this repo (fmt, validate, native tests, policy tests, plan) and write tftest files the repo's way.
---

# Verify Terraform changes locally

Mirrors CI (`.github/workflows/terraform.yml`, `docs/ci.md`). Run from the repo root.

```bash
source .env.aws
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev validate
terraform init -test-directory=tests/terraform        # also after adding a module ref
terraform test -test-directory=tests/terraform        # add -filter=tests/terraform/<file>.tftest.hcl for one file
python3 tests/policy/spend_quality_checks.py
python3 tests/policy/usecase_schema_checks.py
python3 tests/policy/doc_path_refs.py
```

Plan (needs Langfuse env; vars are ephemeral):
```bash
source .env.langfuse
export TF_VAR_langfuse_public_key="$LANGFUSE_PUBLIC_KEY" TF_VAR_langfuse_secret_key="$LANGFUSE_SECRET_KEY" TF_VAR_langfuse_host="$LANGFUSE_HOST"
terraform -chdir=terraform/environments/dev plan
```
`scripts/ci/check_no_secret_material_in_plan.sh` is the CI guard against secrets in a plan.

## Gotchas
- `-test-directory` must be a subdirectory of the config dir: run `init`/`test` from the repo root (empty root config), never with `..`.
- Report failures with the output; don't skip steps silently.

## Writing a tftest (`tests/terraform/*.tftest.hcl`)
Copy `positive_contract.tftest.hcl`:
- real `provider "aws"` with fake keys and all four `skip_*` flags `true`;
- `override_data` for `data.aws_caller_identity.current` (only `account_id`);
- `command = plan`, so nothing is created and no credentials are needed;
- each `run` has its own `module { source = "./terraform/modules/<name>" }` (repo-root-relative);
- no project-wide `mock_provider "aws"`: it also mocks `aws_iam_policy_document`, whose real output the tests assert on.
Add both a positive and a negative (`expect_failures`) case for contract changes.
