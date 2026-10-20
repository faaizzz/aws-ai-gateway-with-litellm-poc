# Proves virtual_key.tf's for_each = module.use_case shape actually produces
# one independent, correctly-scoped virtual-key secret per declared use case.

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
  target = module.use_case["alpha-example"].data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = module.use_case["beta-example"].data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

run "two_use_cases_get_two_independent_scoped_virtual_keys" {
  command = plan

  module {
    source = "./tests/terraform/fixtures/virtual_key_root"
  }

  variables {
    usecases_dir = "./tests/terraform/fixtures/usecases_two_valid"
  }

  assert {
    condition     = length(output.app_key_secret_names) == 2
    error_message = "expected exactly 2 app-key secrets, one per declared use case, got ${length(output.app_key_secret_names)}"
  }

  assert {
    condition     = output.app_key_secret_names["alpha-example"] != output.app_key_secret_names["beta-example"]
    error_message = "the two use cases' app-key secrets must not share a name (i.e. must not share a secret)"
  }

  assert {
    condition     = strcontains(output.app_key_secret_names["alpha-example"], "alpha-example") && strcontains(output.app_key_secret_names["beta-example"], "beta-example")
    error_message = "each use case's secret name must be derived from its own resource_names, not a shared/hardcoded value"
  }

  assert {
    condition     = output.virtual_key_routes["alpha-example"] == "anthropic-claude-haiku-bedrock" && output.virtual_key_routes["beta-example"] == "anthropic-claude-haiku-bedrock"
    error_message = "each use case's virtual key must be scoped to its own resolved route"
  }

  assert {
    condition     = output.virtual_key_models_json["alpha-example"] == jsonencode(["anthropic-claude-haiku-bedrock"]) && output.virtual_key_models_json["beta-example"] == jsonencode(["anthropic-claude-haiku-bedrock"])
    error_message = "each use case's key must carry only its own resolved route in allowed_models, never the full catalogue"
  }

  assert {
    condition     = output.virtual_key_max_budgets["alpha-example"] == 100 && output.virtual_key_max_budgets["beta-example"] == 50
    error_message = "each use case's max_budget must come from its own declaration, not a shared/hardcoded value"
  }
}
