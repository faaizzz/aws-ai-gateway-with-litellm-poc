# Negative contract tests: each of these must fail at `terraform plan`, never
# at runtime.

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
    # Only account_id is used by this module.
    account_id = "123456789012"
  }
}

variables {
  gateway_role_name = "ai-gateway-task-role"
}

run "unknown_model_route_fails" {
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
      model_route         = "does-not-exist-in-catalogue"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "confidential_plus_unapproved_external_provider_fails" {
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
      model_route         = "external-llm-zdr" # real catalogue entry; not approved for confidential
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "invalid_classification_fails" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "top-secret"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "restricted_classification_denied_by_default" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "restricted"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "zero_budget_fails" {
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
      budget              = { monthly_usd = 0 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "negative_budget_fails" {
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
      budget              = { monthly_usd = -500 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "invalid_observability_tier_fails" {
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
      observability       = { tier = "maximum" }
    }
  }

  expect_failures = [var.use_case]
}

run "missing_owner_fails" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = ""
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "missing_team_fails" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = ""
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}

run "confidential_non_eu_route_fails" {
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
      # Test-fixture route: approved for confidential but resolves to a
      # non-EU region.
      model_route   = "hypothetical-non-eu-confidential-fixture"
      budget        = { monthly_usd = 10000 }
      observability = { tier = "standard" }
    }

    catalog_path = "./tests/terraform/fixtures/approved-models-eu-precondition-fixture.yaml"
  }

  expect_failures = [var.use_case]
}

run "invalid_use_case_id_fails" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "Advisor_Chat!"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "confidential"
      model_route         = "anthropic-claude-sonnet-bedrock"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  expect_failures = [var.use_case]
}
