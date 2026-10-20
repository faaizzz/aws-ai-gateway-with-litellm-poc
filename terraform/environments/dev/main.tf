# Dev/demo environment: reads the product team's YAML contract and wires it
# into the platform-owned use-case module, and instantiates the shared gateway
# runtime module.

module "llm_gateway" {
  source = "../../modules/llm-gateway"

  vpc_id          = data.aws_vpc.default.id
  vpc_cidr_block  = data.aws_vpc.default.cidr_block
  subnet_ids      = data.aws_subnets.default.ids
  certificate_arn = aws_acm_certificate.demo.arn
  litellm_image   = "ghcr.io/berriai/litellm:v1.102.1" # pinned release, not main-latest - see terraform/modules/llm-gateway/ecs.tf

  gateway_ci_plan_role_arn  = var.ci_plan_role_arn
  gateway_ci_apply_role_arn = var.ci_apply_role_arn
  local_operator_arns       = var.local_operator_arns

  langfuse_public_key = var.langfuse_public_key
  langfuse_secret_key = var.langfuse_secret_key
  langfuse_host       = var.langfuse_host
}

# Safety net: two declarations sharing a metadata.id would otherwise silently
# pick just one of them.
resource "terraform_data" "usecase_id_uniqueness" {
  input = length(local.usecase_files)

  lifecycle {
    precondition {
      condition = alltrue([
        for id, decls in local.usecase_declarations_grouped : length(decls) == 1
      ])
      error_message = "Two or more usecases/*.yaml files declare the same metadata.id: ${join(", ", [for id, decls in local.usecase_declarations_grouped : id if length(decls) > 1])}. Each declaration's metadata.id must be unique."
    }
  }
}

resource "terraform_data" "usecase_contract_shape" {
  for_each = local.usecase_declarations
  input    = each.value.metadata.id

  lifecycle {
    precondition {
      condition     = length(setsubtract(keys(each.value), local.usecase_contract_top_level_keys)) == 0
      error_message = "usecases/*.yaml declaration \"${each.key}\" has unknown top-level key(s): ${join(", ", setsubtract(keys(each.value), local.usecase_contract_top_level_keys))}. Allowed: ${join(", ", local.usecase_contract_top_level_keys)}."
    }

    precondition {
      condition     = each.value.apiVersion == "ai-platform.example.com/v1"
      error_message = "usecases/*.yaml declaration \"${each.key}\" apiVersion must be \"ai-platform.example.com/v1\", got \"${each.value.apiVersion}\"."
    }

    precondition {
      condition     = each.value.kind == "AIUseCase"
      error_message = "usecases/*.yaml declaration \"${each.key}\" kind must be \"AIUseCase\", got \"${each.value.kind}\"."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value.metadata), local.usecase_contract_metadata_keys)) == 0
      error_message = "usecases/*.yaml declaration \"${each.key}\" metadata has unknown key(s): ${join(", ", setsubtract(keys(each.value.metadata), local.usecase_contract_metadata_keys))}. Allowed: ${join(", ", local.usecase_contract_metadata_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value.spec), local.usecase_contract_spec_keys)) == 0
      error_message = "usecases/*.yaml declaration \"${each.key}\" spec has unknown key(s): ${join(", ", setsubtract(keys(each.value.spec), local.usecase_contract_spec_keys))}. Allowed: ${join(", ", local.usecase_contract_spec_keys)}."
    }
  }
}

module "use_case" {
  for_each = local.usecase_declarations
  source   = "../../modules/use-case"

  gateway_role_name = module.llm_gateway.gateway_task_role_name
  environment       = "dev" # this is the dev/demo environment; platform-owned, not part of the use_case declaration

  # Explicit rather than relying on the module's own default: this is the
  # real, deployed environment, so it always resolves the real production
  # catalogue.
  catalog_path = "${path.module}/../../catalog/approved-models.yaml"

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

# Per-use-case AWS Budget alarm, one instance per module.use_case instance -
# unlike the shared gateway above.
module "use_case_observability" {
  for_each = module.use_case
  source   = "../../modules/use-case-observability"

  attribution    = each.value.attribution
  resource_names = each.value.resource_names
  budget_config  = each.value.budget_config
  environment    = "dev"
}
