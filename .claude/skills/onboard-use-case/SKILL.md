---
name: onboard-use-case
description: Onboard a new AI use case in this repo by adding usecases/<id>.yaml, wiring it into the dev environment, and adding tests.
---

# Onboard a use case

Read `terraform/modules/use-case/README.md` and `usecases/digestbot.yaml` (template) first.

1. **Declaration** `usecases/<id>.yaml`: `apiVersion: ai-platform.example.com/v1`, `kind: AIUseCase`; `metadata.id/owner/team`; `spec.dataClassification`, `spec.modelRoute`, `spec.budget.monthlyUsd`, `spec.observability.tier` (`minimal|standard`).
   - id: lowercase letters/digits/hyphens, starts with a letter, bounded length, immutable.
   - Teams never set provider/model IDs, IAM, or LiteLLM settings.
2. **Route and classification**: `modelRoute` must exist in `terraform/catalog/approved-models.yaml` and allow the classification. `restricted` is denied; `confidential` only on routes approved for it (the external provider is not).
3. **Budget**: label it as an ASSUMPTION in a comment with its % over observed spend from `data/sample_spend_30d.csv`.
4. **Wiring is automatic**: `terraform/environments/dev/main.tf` does `for_each` over `usecases/*.yaml` (unknown keys, apiVersion/kind and duplicate ids are rejected there). No per-use-case code edit; check `plan` shows the new `module.use_case["<id>"]` and its virtual key.
5. **Tests**: add positive (and negative where relevant) cases in `tests/terraform/` (see `tf-verify`).
6. Run `python3 tests/policy/usecase_schema_checks.py`, then the `tf-verify` sequence.
7. Update the use-case list in docs if one exists (`doc_path_refs.py` must pass).
