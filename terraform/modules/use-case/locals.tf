# Split out of main.tf by concern - pure move, no functional change.

locals {
  # ---- Deterministic naming ----
  resource_names = {
    identity      = "ai-usecase-${var.use_case.id}"
    gateway       = "ai-gateway-${var.use_case.id}"
    budget        = "ai-budget-${var.use_case.id}"
    observability = "ai-observability-${var.use_case.id}"
  }

  # ---- Platform-owned attribution ----
  # Carried on every request by the gateway; never caller-supplied.
  attribution = {
    use_case_id         = var.use_case.id
    team                = var.use_case.team
    owner               = var.use_case.owner
    data_classification = var.use_case.data_classification
    route               = var.use_case.model_route
    provider            = local.route_exists ? local.resolved_route.provider : null
  }

  # ---- Classification-derived safe defaults ----
  # Derived from the declared classification, never set by the product team.
  safe_defaults = {
    # Audit-grade trace retention: longer for data that regulators/DPO may
    # need reconstructed later; short for public/internal chat-style traffic.
    trace_retention_days = (
      var.use_case.data_classification == "confidential" ? 180 :
      var.use_case.data_classification == "internal" ? 60 : 30
    )

    audit_log_required = contains(
      ["confidential", "restricted"], var.use_case.data_classification
    )

    # Non-negotiable platform invariant, not actually classification-
    # varying: Datadog only ever receives derived metrics, never
    # prompt/response content, for any classification.
    content_in_datadog_allowed = false

    # Both current catalogue routes already resolve to EU-only infrastructure;
    # this flag documents the policy intent for future non-EU routes.
    eu_only_routing_required = contains(
      ["confidential", "restricted"], var.use_case.data_classification
    )
  }

  # ---- Budget configuration ----
  # This module itself emits metadata + thresholds only, no alarm resources
  # - AWS Budgets is account/billing-scoped infrastructure, not a per-module
  # concern.
  budget_config = {
    monthly_usd      = var.use_case.budget.monthly_usd
    thresholds_pct   = [75, 90, 100]
    owner            = var.use_case.owner
    attribution      = local.attribution
    enforcement_note = "Terraform establishes budget metadata and thresholds here; terraform/modules/use-case-observability provisions the actual threshold alarms from them (budget.tf). Current-spend checks and request-blocking/downgrade decisions are made by the gateway at runtime, not by Terraform."
  }

  # ---- Observability-tier configuration ----
  observability_config = {
    tier = var.use_case.observability.tier
    metric_dimensions = {
      team        = var.use_case.team
      use_case_id = var.use_case.id
      route       = var.use_case.model_route
      provider    = local.attribution.provider
      environment = var.environment
    }
    metrics = var.use_case.observability.tier == "standard" ? [
      "llm_requests_total",
      "llm_request_errors_total",
      "llm_provider_throttles_total",
      "llm_input_tokens_total",
      "llm_output_tokens_total",
      "llm_cost_usd_total",
      "llm_request_duration_seconds",
      ] : [
      "llm_requests_total",
      "llm_request_errors_total",
    ]
    content_allowed_in_datadog = false
    trace_destination          = "langfuse"
  }
}
