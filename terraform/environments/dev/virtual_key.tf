# A route-scoped virtual key per declared use case, issued through LiteLLM's
# own /key/generate API rather than a Terraform-generated random value.

resource "aws_secretsmanager_secret" "app_key" {
  for_each = module.use_case

  name        = "${each.value.resource_names.gateway}-app-key"
  description = "Route-scoped LiteLLM virtual key for use case \"${each.value.attribution.use_case_id}\" (route: ${each.value.attribution.route}), issued via /key/generate. This - not the platform master key - is the application's credential."
}

data "aws_iam_policy_document" "app_key_secret_policy" {
  for_each = module.use_case

  statement {
    sid    = "AllowPlatformDeployerReadOnly"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.app_key_readers
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_key[each.key].arn]
  }

  statement {
    sid    = "DenyEveryoneElse"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_key[each.key].arn]
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.app_key_readers
    }
  }
}

resource "aws_secretsmanager_secret_policy" "app_key_read_only" {
  for_each = module.use_case

  secret_arn = aws_secretsmanager_secret.app_key[each.key].arn
  policy     = data.aws_iam_policy_document.app_key_secret_policy[each.key].json

  # Safety net: with app_key_reader_arns folding in the CI apply role ARN,
  # this should never actually render empty.
  lifecycle {
    precondition {
      condition     = length(local.app_key_readers) > 0
      error_message = "app_key_readers must never be empty - AWS Secrets Manager rejects a resource policy whose Allow statement has no principals. At least one of: an IAM-user caller identity running Terraform, var.local_operator_arns, or var.ci_apply_role_arn (the CI OIDC apply role) must resolve to a real ARN."
    }
  }
}

# Idempotent create-or-sync.
resource "terraform_data" "virtual_key" {
  for_each = module.use_case

  triggers_replace = {
    key_alias   = local.virtual_key_aliases[each.key]
    models_json = jsonencode(each.value.virtual_key_allowed_models)
    max_budget  = each.value.budget_config.monthly_usd
    soft_budget = local.virtual_key_soft_budgets[each.key]
    # Attribution is a trigger too, so changing e.g.
    metadata = jsonencode(each.value.attribution)
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/ensure_virtual_key.sh\""

    environment = {
      GATEWAY_URL           = "https://${module.llm_gateway.alb_dns_name}"
      MASTER_KEY_SECRET_ARN = module.llm_gateway.gateway_key_secret_arn
      TARGET_SECRET_ID      = aws_secretsmanager_secret.app_key[each.key].id
      KEY_ALIAS             = local.virtual_key_aliases[each.key]
      # Always the module's own virtual_key_allowed_models output - a
      # single-element list containing only the resolved route - never
      # hand-assembled here.
      MODELS_JSON   = jsonencode(each.value.virtual_key_allowed_models)
      MAX_BUDGET    = tostring(each.value.budget_config.monthly_usd)
      SOFT_BUDGET   = tostring(local.virtual_key_soft_budgets[each.key])
      USE_CASE_ID   = each.value.attribution.use_case_id
      ROUTE         = each.value.attribution.route
      METADATA_JSON = jsonencode(each.value.attribution)
    }
  }

  # depends_on the whole gateway module, not an individual resource inside
  # it - the module boundary is the right dependency granularity now that
  # ecs.tf/etc.
  depends_on = [
    module.llm_gateway,
    aws_secretsmanager_secret.app_key,
    aws_secretsmanager_secret_policy.app_key_read_only,
  ]
}

# output "app_key_secret_arns" lives in outputs.tf.
