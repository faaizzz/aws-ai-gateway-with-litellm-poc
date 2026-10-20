# Platform-owned use-case module interface.

variable "use_case" {
  description = "A product team's self-service onboarding contract for one AI use case."

  type = object({
    id                  = string
    team                = string
    owner               = string
    data_classification = string
    model_route         = string

    budget = object({
      monthly_usd = number
    })

    observability = object({
      tier = string
    })
  })

  validation {
    # A missing field already fails object type conversion before this runs.
    # This only catches an empty-string id, which type conversion allows.
    condition     = length(trimspace(var.use_case.id)) > 0
    error_message = "use_case.id must not be empty."
  }

  validation {
    # Naming rule: lowercase, numbers, hyphens;
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}$", var.use_case.id))
    error_message = "use_case.id must start with a lowercase letter and contain only lowercase letters, numbers and hyphens (2-39 chars)."
  }

  validation {
    condition     = length(trimspace(var.use_case.team)) > 0
    error_message = "use_case.team must not be empty. Attribution must never be blank (CLAUDE.md invariants)."
  }

  validation {
    condition     = length(trimspace(var.use_case.owner)) > 0
    error_message = "use_case.owner must not be empty."
  }

  validation {
    condition = contains(
      ["public", "internal", "confidential", "restricted"],
      var.use_case.data_classification
    )
    error_message = "use_case.data_classification must be one of: public, internal, confidential, restricted."
  }

  validation {
    condition     = var.use_case.data_classification != "restricted"
    error_message = "use_case.data_classification \"restricted\" is denied by default for this PoC — no catalogue route is approved for it."
  }

  validation {
    condition     = length(trimspace(var.use_case.model_route)) > 0
    error_message = "use_case.model_route must not be empty."
  }

  validation {
    condition     = var.use_case.budget.monthly_usd > 0
    error_message = "use_case.budget.monthly_usd must be greater than zero."
  }

  validation {
    condition = contains(
      ["minimal", "standard"],
      var.use_case.observability.tier
    )
    error_message = "use_case.observability.tier must be one of: minimal, standard."
  }

  # ---- Cross-field checks against the platform catalogue ----
  validation {
    condition     = contains(keys(local.catalog.routes), var.use_case.model_route)
    error_message = "use_case.model_route \"${var.use_case.model_route}\" is not in the approved catalogue (terraform/catalog/approved-models.yaml)."
  }

  validation {
    condition = contains(
      try(local.catalog.routes[var.use_case.model_route].allowed_classifications, []),
      var.use_case.data_classification
    )
    error_message = "Classification \"${var.use_case.data_classification}\" is not approved for route \"${var.use_case.model_route}\". Approved classifications for this route: ${contains(keys(local.catalog.routes), var.use_case.model_route) ? join(", ", local.catalog.routes[var.use_case.model_route].allowed_classifications) : "n/a - route unknown"}."
  }

  validation {
    # Enforces safe_defaults.eu_only_routing_required rather than leaving
    # it output-only.
    condition = (
      var.use_case.data_classification != "confidential" ||
      (
        contains(keys(local.catalog.routes), var.use_case.model_route) &&
        length(try(local.catalog.routes[var.use_case.model_route].profile_regions, [])) > 0 &&
        alltrue([
          for region in try(local.catalog.routes[var.use_case.model_route].profile_regions, []) : can(regex("^eu-", region))
        ])
      )
    )
    error_message = "use_case.data_classification \"confidential\" requires a route whose profile_regions are all EU region codes (eu-*). Route \"${var.use_case.model_route}\" resolves to region(s): ${contains(keys(local.catalog.routes), var.use_case.model_route) ? join(", ", try(local.catalog.routes[var.use_case.model_route].profile_regions, [])) : "n/a - route unknown"}."
  }
}

variable "catalog_path" {
  description = "Path to the model catalogue. null uses terraform/catalog/approved-models.yaml. Test-only override for fixture catalogues; real declarations never set it."
  type        = string
  nullable    = true
  default     = null
}

variable "gateway_role_name" {
  description = <<-EOT
    Name of the shared gateway ECS task role (created by terraform/modules/llm-gateway). The module attaches an inline policy scoped to this use case's route and never owns the role.
  EOT
  type        = string
}

variable "environment" {
  description = <<-EOT
    Deployment environment for this use case (e.g. "dev", "staging", "prod"),
    stamped as a Datadog metric dimension alongside team/use_case_id/route/
    provider (CLAUDE.md "Observability split"). Platform-owned
    like gateway_role_name/gateway_role_arn - never set by the product
    team's use_case declaration - so it defaults to "dev" for this PoC's
    single environment rather than being required.
  EOT
  type        = string
  default     = "dev"
}

# gateway_task_execution_role_arn, gateway_ci_plan_role_arn,
# gateway_ci_apply_role_arn and local_operator_arns used to live here.
