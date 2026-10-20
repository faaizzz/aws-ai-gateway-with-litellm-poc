# Moved out of terraform/modules/use-case/secrets.tf verbatim plus
# terraform/environments/dev/langfuse.tf.
locals {
  gateway_name = "ai-gateway-advisor-chat"
}

data "aws_caller_identity" "current" {}

# ---- Gateway master key ----
# This is the PLATFORM's master key, not the application's credential.
ephemeral "random_password" "gateway_key" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "gateway_key" {
  name        = "${local.gateway_name}-key"
  description = "Platform master key for the shared LiteLLM gateway. Readable by the gateway task role only."
}

resource "aws_secretsmanager_secret_version" "gateway_key" {
  secret_id = aws_secretsmanager_secret.gateway_key.id

  # Write-only: Terraform never diffs or persists this value — only
  # secret_string_wo_version is compared between plans.
  secret_string_wo = jsonencode({
    key = ephemeral.random_password.gateway_key.result
  })
  secret_string_wo_version = 1
}

# ---- LiteLLM DB encryption salt ----
# LiteLLM persists virtual keys and team config in its own Postgres database
# and, absent an explicit LITELLM_SALT_KEY.
ephemeral "random_password" "gateway_salt_key" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "gateway_salt_key" {
  name        = "${local.gateway_name}-salt-key"
  description = "Stable LiteLLM DB-encryption salt (LITELLM_SALT_KEY) for the shared gateway. Decoupled from the gateway master key so master-key rotation never breaks already-persisted virtual keys. Readable by the gateway task role only."
}

resource "aws_secretsmanager_secret_version" "gateway_salt_key" {
  secret_id                = aws_secretsmanager_secret.gateway_salt_key.id
  secret_string_wo         = ephemeral.random_password.gateway_salt_key.result
  secret_string_wo_version = 1
}

# ---- Langfuse Cloud API keys ----
# Credentials for the LiteLLM -> Langfuse trace callback.
resource "aws_secretsmanager_secret" "langfuse_keys" {
  name        = "${local.gateway_name}-langfuse-keys"
  description = "Langfuse Cloud API keys for the LiteLLM trace callback. Readable by the gateway task execution role only."
}

resource "aws_secretsmanager_secret_version" "langfuse_keys" {
  secret_id = aws_secretsmanager_secret.langfuse_keys.id

  secret_string_wo = jsonencode({
    public_key = var.langfuse_public_key
    secret_key = var.langfuse_secret_key
  })
  secret_string_wo_version = 1
}

locals {
  # The caller identity is a stable reader only if it is an IAM user, not a
  # GitHub OIDC assumed role.
  stable_secret_reader_arns = distinct(compact(concat(
    [
      for arn in [data.aws_caller_identity.current.arn] : arn
      if can(regex(":user/", arn))
    ],
    var.local_operator_arns,
  )))

  # Principals that may read the gateway key secrets.
  gateway_key_readers = distinct(compact(concat(
    [
      aws_iam_role.gateway_task_role.arn,
      aws_iam_role.gateway_task_execution_role.arn,
      var.gateway_ci_plan_role_arn,
      var.gateway_ci_apply_role_arn,
    ],
    local.stable_secret_reader_arns,
  )))

  # Can be empty without the CI apply role; guarded below.
  app_key_reader_arns = distinct(compact(concat(
    local.stable_secret_reader_arns,
    [var.gateway_ci_apply_role_arn],
  )))
}

data "aws_iam_policy_document" "gateway_key_secret_policy" {
  statement {
    sid    = "AllowGatewayRoleAndDeployerReadOnly"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.gateway_key_readers
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.gateway_key.arn]
  }

  statement {
    sid    = "DenyEveryoneElse"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.gateway_key.arn]
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.gateway_key_readers
    }
  }
}

resource "aws_secretsmanager_secret_policy" "gateway_key_read_only" {
  secret_arn = aws_secretsmanager_secret.gateway_key.arn
  policy     = data.aws_iam_policy_document.gateway_key_secret_policy.json

  # Secrets Manager rejects a policy with no principals.
  lifecycle {
    precondition {
      condition     = length(local.gateway_key_readers) > 0
      error_message = "gateway_key_readers must never be empty - AWS Secrets Manager rejects a resource policy whose Allow statement has no principals."
    }
  }
}

# Same readers as the master key.
data "aws_iam_policy_document" "gateway_salt_key_secret_policy" {
  statement {
    sid    = "AllowGatewayRoleAndDeployerReadOnly"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.gateway_key_readers
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.gateway_salt_key.arn]
  }

  statement {
    sid    = "DenyEveryoneElse"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.gateway_salt_key.arn]
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.gateway_key_readers
    }
  }
}

resource "aws_secretsmanager_secret_policy" "gateway_salt_key_read_only" {
  secret_arn = aws_secretsmanager_secret.gateway_salt_key.arn
  policy     = data.aws_iam_policy_document.gateway_salt_key_secret_policy.json

  lifecycle {
    precondition {
      condition     = length(local.gateway_key_readers) > 0
      error_message = "gateway_key_readers must never be empty - AWS Secrets Manager rejects a resource policy whose Allow statement has no principals."
    }
  }
}

# Fails the plan if app_key_reader_arns is empty.
resource "terraform_data" "app_key_reader_safety_net" {
  input = local.gateway_name

  lifecycle {
    precondition {
      condition     = length(local.app_key_reader_arns) > 0
      error_message = "app_key_reader_arns must never be empty - AWS Secrets Manager rejects an app-key secret's resource policy whose Allow statement has no principals. At least one of: an IAM-user caller identity running Terraform, var.local_operator_arns, or var.gateway_ci_apply_role_arn (the CI OIDC apply role) must resolve to a real ARN."
    }
  }
}
