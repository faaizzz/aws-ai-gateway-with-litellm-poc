---
name: terraform-standards
description: Repo conventions for writing or changing Terraform in this repo (modules, validation, IAM, security-group rules, trivy/tflint). Use before editing anything under terraform/.
---

# Terraform standards (this repo)

Source of truth: `CLAUDE.md` "Invariants", `docs/known-limitations.md`, `.tflint.hcl`, existing modules. When unsure, copy the nearest existing module.

## Layout
- Modules in `terraform/modules/<name>`: one file per resource group (`alb.tf`, `ecs.tf`, `iam.tf`, `rds.tf`, `secrets.tf`, ...), plus `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`, `README.md`. New modules get no `main.tf` (`use-case/main.tf` is a leftover).
- Env roots (`terraform/environments/dev`): a small wiring-only `main.tf`; no resources of their own beyond wiring.
- Resource names are deterministic: `ai-<kind>-<id>`. Use-case ids: lowercase letters/digits/hyphens, start with a letter, bounded length, immutable.
- Root `required_version >= 1.11.0` (write-only secret attributes). State in S3, `use_lockfile = true`. Never commit state, `*.tfvars`, credentials.

## Validation
- Cross-field checks against the catalogue use variable `validation` (Terraform >= 1.9) or `lifecycle` preconditions, so bad input fails at plan time.
- Missing object fields fail type conversion, but empty strings do not: add non-empty checks for `id`, `team`, `owner`.
- `langfuse_host` is validated to the EU host only.

## Security
- IAM: only `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on specific model/profile ARNs, granted to the gateway task role only. Never `bedrock:*` or `*`. `eu.` inference profiles need the profile ARN plus foundation-model ARNs in each EU region.
- Secrets: Secrets Manager, written with `secret_string_wo` + `secret_string_wo_version`, inputs `ephemeral = true`; injected into ECS as `secrets`, never plaintext env. No credentials in outputs.
- Security-group rules are standalone resources, not inline.
- No NAT gateway, EKS, multi-region.
- Accepted deviations are silenced inline with `# trivy:ignore:<ID>` plus a reason, and listed in `docs/known-limitations.md`.

## Before finishing
Run the `tf-verify` skill.
