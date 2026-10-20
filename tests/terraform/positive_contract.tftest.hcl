# Positive contract test: AdvisorChat's real declaration must plan cleanly.

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

  use_case = {
    id                  = "advisor-chat"
    team                = "advisor"
    owner               = "advisor-platform"
    data_classification = "confidential"
    model_route         = "anthropic-claude-sonnet-bedrock"

    budget = {
      monthly_usd = 10000
    }

    observability = {
      tier = "standard"
    }
  }
}

run "advisor_chat_plans_successfully" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  assert {
    condition     = output.resolved_route.provider == "bedrock"
    error_message = "AdvisorChat's route must resolve to the Bedrock catalogue entry."
  }

  assert {
    condition     = contains(output.resolved_route.allowed_classifications, "confidential")
    error_message = "The resolved route must be approved for the confidential classification AdvisorChat declares."
  }

  assert {
    condition     = output.attribution.use_case_id == "advisor-chat" && output.attribution.team == "advisor"
    error_message = "Attribution must be derived from the declaration, not left blank or overridable."
  }

  assert {
    condition     = output.resource_names.gateway == "ai-gateway-advisor-chat"
    error_message = "Resource names must follow the ai-<kind>-<id> naming convention."
  }

  assert {
    condition     = output.safe_defaults.audit_log_required == true
    error_message = "Confidential data must get audit_log_required = true by default."
  }

  assert {
    condition     = output.safe_defaults.content_in_datadog_allowed == false
    error_message = "No classification may ever allow content into Datadog."
  }

  assert {
    condition     = output.iam_policy_json != null
    error_message = "A Bedrock-routed use case must produce an IAM policy document."
  }
}
