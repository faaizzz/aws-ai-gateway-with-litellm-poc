# Test fixture: reproduces virtual_key.tf's own for_each = module.use_case
# resource shape against two real module.use_case instances.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0, < 6.0.0"
    }
  }
}

variable "usecases_dir" {
  type = string
}

locals {
  usecase_files = fileset(var.usecases_dir, "*.yaml")

  usecase_declarations = {
    for f in local.usecase_files :
    yamldecode(file("${var.usecases_dir}/${f}")).metadata.id => yamldecode(file("${var.usecases_dir}/${f}"))
  }

  # Stand-ins for module.llm_gateway's outputs - plain values, not a real
  # gateway stack (see file header).
  fake_alb_dns_name           = "fake-gateway-alb.example.com"
  fake_gateway_key_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:fake-gateway-key-AbCdEf"
  fake_app_key_readers        = ["arn:aws:iam::123456789012:user/fake-deployer"]

  virtual_key_aliases = {
    for id, uc in module.use_case : id => "${uc.resource_names.gateway}-app-key"
  }

  # LiteLLM soft_budget: the warning tier, at the lowest declared threshold
  # (75%). LiteLLM alerts when a key's spend crosses it; only max_budget blocks.
  virtual_key_soft_budgets = {
    for id, uc in module.use_case : id => uc.budget_config.monthly_usd * min(uc.budget_config.thresholds_pct...) / 100
  }
}

module "use_case" {
  for_each = local.usecase_declarations
  source   = "../../../../terraform/modules/use-case"

  gateway_role_name = "ai-gateway-task-role"
  environment       = "test"

  use_case = {
    id                  = each.value.metadata.id
    team                = each.value.metadata.team
    owner               = each.value.metadata.owner
    data_classification = each.value.spec.dataClassification
    model_route         = each.value.spec.modelRoute

    budget = {
      monthly_usd = each.value.spec.budget.monthlyUsd
    }

    observability = {
      tier = each.value.spec.observability.tier
    }
  }
}

resource "aws_secretsmanager_secret" "app_key" {
  for_each = module.use_case

  name        = "${each.value.resource_names.gateway}-app-key"
  description = "Route-scoped LiteLLM virtual key for use case \"${each.value.attribution.use_case_id}\" (route: ${each.value.attribution.route})."
}

data "aws_iam_policy_document" "app_key_secret_policy" {
  for_each = module.use_case

  statement {
    sid    = "AllowPlatformDeployerReadOnly"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.fake_app_key_readers
    }
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_key[each.key].arn]
  }
}

resource "aws_secretsmanager_secret_policy" "app_key_read_only" {
  for_each = module.use_case

  secret_arn = aws_secretsmanager_secret.app_key[each.key].arn
  policy     = data.aws_iam_policy_document.app_key_secret_policy[each.key].json
}

resource "terraform_data" "virtual_key" {
  for_each = module.use_case

  triggers_replace = {
    key_alias   = local.virtual_key_aliases[each.key]
    models_json = jsonencode(each.value.virtual_key_allowed_models)
    max_budget  = each.value.budget_config.monthly_usd
    soft_budget = local.virtual_key_soft_budgets[each.key]
    metadata    = jsonencode(each.value.attribution)
  }

  provisioner "local-exec" {
    command = "true" # never actually invoked under `command = plan`

    environment = {
      GATEWAY_URL           = "https://${local.fake_alb_dns_name}"
      MASTER_KEY_SECRET_ARN = local.fake_gateway_key_secret_arn
      TARGET_SECRET_ID      = aws_secretsmanager_secret.app_key[each.key].id
      KEY_ALIAS             = local.virtual_key_aliases[each.key]
      MODELS_JSON           = jsonencode(each.value.virtual_key_allowed_models)
      MAX_BUDGET            = tostring(each.value.budget_config.monthly_usd)
      SOFT_BUDGET           = tostring(local.virtual_key_soft_budgets[each.key])
      USE_CASE_ID           = each.value.attribution.use_case_id
      ROUTE                 = each.value.attribution.route
      METADATA_JSON         = jsonencode(each.value.attribution)
    }
  }
}

output "app_key_secret_names" {
  value = { for id, s in aws_secretsmanager_secret.app_key : id => s.name }
}

output "virtual_key_routes" {
  value = { for id, m in module.use_case : id => m.attribution.route }
}

output "virtual_key_models_json" {
  value = { for id, m in module.use_case : id => jsonencode(m.virtual_key_allowed_models) }
}

output "virtual_key_max_budgets" {
  value = { for id, m in module.use_case : id => m.budget_config.monthly_usd }
}
