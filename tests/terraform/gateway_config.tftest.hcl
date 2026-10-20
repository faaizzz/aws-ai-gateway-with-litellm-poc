# Gateway route/budget/observability config tests.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    # Only .account_id is used by this module now - .arn moved to
    # terraform/modules/llm-gateway with that list, so this override no
    # longer needs to shape it at all.
    account_id = "123456789012"
  }
}

variables {
  gateway_role_name = "ai-gateway-task-role"
}

run "route_resolves_from_catalogue_with_platform_attribution" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  assert {
    condition     = output.attribution.route == "anthropic-claude-sonnet-bedrock"
    error_message = "The application must only ever see the logical route name, never a concrete model ID."
  }

  assert {
    condition     = output.resolved_route.model_id == "eu.anthropic.claude-sonnet-4-6"
    error_message = "The concrete model ID must come from the catalogue resolution, not be settable by the product team."
  }

  assert {
    condition     = output.attribution.use_case_id == "advisor-chat" && output.attribution.team == "advisor"
    error_message = "Attribution must be platform-owned, derived from the declaration, never from caller headers."
  }
}

run "virtual_key_allowed_models_equals_resolved_route_only" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  # Since route-scoping is enforced by the VIRTUAL KEY's allowed-models
  # list, not by the gateway's model_list having exactly one entry.
  assert {
    condition     = output.virtual_key_allowed_models == [var.use_case.model_route]
    error_message = "virtual_key_allowed_models must be exactly a single-element list containing the resolved route - never the full catalogue, a wildcard, or additional routes."
  }

  assert {
    condition     = length(output.virtual_key_allowed_models) == 1
    error_message = "A use case's virtual key must be scoped to exactly one route."
  }
}

run "budget_config_has_three_thresholds_and_owner_attribution" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  assert {
    condition     = output.budget_config.monthly_usd == 10000
    error_message = "Budget config must reflect the declared monthly_usd (the AdvisorChat $10k figure is a stated assumption, not inferred - see README.md)."
  }

  assert {
    condition     = output.budget_config.thresholds_pct == [75, 90, 100]
    error_message = "Budget thresholds must be 75/90/100."
  }

  assert {
    condition     = output.budget_config.owner == "advisor-platform"
    error_message = "The alarm/notification target must derive from the declared owner."
  }
}

run "standard_observability_tier_has_full_metric_set" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  assert {
    condition     = length(output.observability_config.metrics) == 7
    error_message = "The standard tier must cover request count, errors, throttles, tokens (in/out), cost and latency."
  }

  assert {
    condition     = output.observability_config.content_allowed_in_datadog == false
    error_message = "No observability tier may allow content into Datadog."
  }

  assert {
    condition     = !contains(keys(output.observability_config.metric_dimensions), "user_id") && !contains(keys(output.observability_config.metric_dimensions), "customer_id")
    error_message = "Metric dimensions must not include high-cardinality user/customer identifiers."
  }
}

run "minimal_observability_tier_has_reduced_metric_set" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "internal"
      model_route         = "anthropic-claude-haiku-bedrock"
      budget              = { monthly_usd = 500 }
      observability       = { tier = "minimal" }
    }
  }

  assert {
    condition     = length(output.observability_config.metrics) < 7
    error_message = "The minimal tier must be a strictly smaller metric set than standard."
  }
}
