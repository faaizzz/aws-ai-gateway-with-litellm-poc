---
name: rotate-secret
description: Rotate the Langfuse keys or gateway master key for the LiteLLM gateway in this repo and roll the running ECS task. Only when the user asks.
disable-model-invocation: true
---

# Rotate a gateway secret

Runbooks: `terraform/modules/llm-gateway/README.md` "Gateway key rotation"; `CLAUDE.md` "Langfuse access". Secrets are in `terraform/modules/llm-gateway/secrets.tf`, written with `secret_string_wo` + `secret_string_wo_version`.

**Langfuse key**
1. Get the new key from the Langfuse Cloud project settings; update `.env.langfuse`.
2. Verify: `source .env.langfuse && curl -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$LANGFUSE_HOST/api/public/projects"` returns the project. Host must be the EU host `https://cloud.langfuse.com`.
3. Bump `secret_string_wo_version` on `aws_secretsmanager_secret_version.langfuse_keys`; export the `TF_VAR_langfuse_*` variables (see `tf-verify`); plan, review, apply (see `apply-plan`).

**Gateway master key**: bump `gateway_key` and follow the README runbook, including re-running `terraform/environments/dev/scripts/ensure_virtual_key.sh` afterwards. **Never bump the salt key's version** after its first apply: it orphans every stored virtual key.

**Always** force a new deployment afterwards, because ECS does not restart a task when a secret's value changes:
```bash
source .env.aws
aws ecs update-service --cluster <cluster> --service ai-gateway-advisor-chat --force-new-deployment
```
Never print secret values or commit them.
