---
name: apply-plan
description: Apply Terraform in this repo through the gated GitHub Actions flow (fresh plan run, then manual terraform-apply dispatch). Only when the user explicitly asks to apply.
disable-model-invocation: true
---

# Apply via Actions

Apply is outward-facing: only run when the user asked for it. Gate details: `docs/ci.md`.

1. Plan on current `main`:
   ```bash
   gh workflow run terraform.yml --ref main
   id=$(gh run list --workflow=terraform.yml --branch=main --limit 1 --json databaseId -q '.[0].databaseId')
   gh run watch $id --exit-status
   ```
2. Read the plan: `gh run view $id --log | grep -E "Plan:|No changes|will be|must be replaced"`. Show destroys/replacements to the user before applying.
3. Apply that exact plan:
   ```bash
   gh workflow run terraform-apply.yml --ref main -f plan_run_id=$id
   ```
   then watch the run.

Notes
- "Saved plan is stale": state changed after the plan. Make a fresh plan run and apply that.
- A "No changes" plan makes the apply a no-op; say so.
- Never `apply -auto-approve` locally against the shared state. Drift detection runs daily (`drift-detection.yml`).
