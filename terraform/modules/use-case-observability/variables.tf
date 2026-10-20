# Per-use-case AWS Budget alarm. Budget notifications are Datadog target state.

variable "attribution" {
  description = "Platform-owned attribution map for one use case (terraform/modules/use-case's attribution output) - team, owner, use_case_id, data_classification, route, provider."
  type = object({
    use_case_id         = string
    team                = string
    owner               = string
    data_classification = string
    route               = string
    provider            = string
  })
}

variable "resource_names" {
  description = "Deterministic resource names for one use case (terraform/modules/use-case's resource_names output) - only `.budget` is used here."
  type = object({
    identity      = string
    gateway       = string
    budget        = string
    observability = string
  })
}

variable "budget_config" {
  description = "Budget metadata and thresholds for one use case (terraform/modules/use-case's budget_config output)."
  type = object({
    monthly_usd      = number
    thresholds_pct   = list(number)
    owner            = string
    attribution      = any
    enforcement_note = string
  })
}

variable "environment" {
  description = "Deployment environment (e.g. \"dev\"), stamped as an `environment` tag on the AWS side - platform-owned, passed straight through from the environment root, same as terraform/modules/use-case's own environment input."
  type        = string
  default     = "dev"
}
