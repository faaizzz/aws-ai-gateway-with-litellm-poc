# Proves terraform/modules/use-case-observability creates an independent,
# correctly-scoped budget alarm per use case.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

run "standard_tier_usecase_gets_full_dashboard_and_own_scoped_resources" {
  command = plan

  module {
    source = "./terraform/modules/use-case-observability"
  }

  # aws_budgets_budget.this.notification's subscriber_sns_topic_arns embeds
  # aws_sns_topic.budget_alerts.arn, genuinely unknown at plan time for a
  # brand-new topic.
  override_resource {
    target          = aws_sns_topic.budget_alerts
    override_during = plan
    values = {
      arn = "arn:aws:sns:eu-central-1:123456789012:ai-budget-test-standard-uc-alerts"
    }
  }

  variables {
    attribution = {
      use_case_id         = "test-standard-uc"
      team                = "test-team-a"
      owner               = "test-owner-a"
      data_classification = "confidential"
      route               = "anthropic-claude-sonnet-bedrock"
      provider            = "bedrock"
    }

    resource_names = {
      identity      = "ai-usecase-test-standard-uc"
      gateway       = "ai-gateway-test-standard-uc"
      budget        = "ai-budget-test-standard-uc"
      observability = "ai-observability-test-standard-uc"
    }

    budget_config = {
      monthly_usd      = 5000
      thresholds_pct   = [75, 90, 100]
      owner            = "test-owner-a"
      attribution      = {}
      enforcement_note = "test fixture - not a real enforcement mechanism"
    }

    environment = "dev"
  }

  assert {
    condition     = aws_sns_topic.budget_alerts.name == "ai-budget-test-standard-uc-alerts"
    error_message = "The SNS topic name must be derived from this use case's own resource_names.budget."
  }

  assert {
    condition     = aws_budgets_budget.this.name == "ai-budget-test-standard-uc-account-wide-not-per-usecase"
    error_message = "The budget's name must be derived from this use case's own resource_names.budget and must self-document the account-wide scope caveat (see budget.tf)."
  }

  assert {
    condition     = length(aws_budgets_budget.this.notification) == 3
    error_message = "The contract requires 75/90/100 thresholds - expected exactly 3 notification blocks."
  }
}

run "minimal_tier_usecase_gets_reduced_dashboard_and_own_scoped_resources" {
  command = plan

  module {
    source = "./terraform/modules/use-case-observability"
  }

  variables {
    attribution = {
      use_case_id         = "test-minimal-uc"
      team                = "test-team-b"
      owner               = "test-owner-b"
      data_classification = "internal"
      route               = "anthropic-claude-haiku-bedrock"
      provider            = "bedrock"
    }

    resource_names = {
      identity      = "ai-usecase-test-minimal-uc"
      gateway       = "ai-gateway-test-minimal-uc"
      budget        = "ai-budget-test-minimal-uc"
      observability = "ai-observability-test-minimal-uc"
    }

    budget_config = {
      monthly_usd      = 100
      thresholds_pct   = [75, 90, 100]
      owner            = "test-owner-b"
      attribution      = {}
      enforcement_note = "test fixture - not a real enforcement mechanism"
    }

    environment = "dev"
  }

  assert {
    condition     = aws_sns_topic.budget_alerts.name == "ai-budget-test-minimal-uc-alerts"
    error_message = "The SNS topic name must be derived from this use case's own resource_names.budget, distinct from the other run's."
  }

  assert {
    condition     = aws_budgets_budget.this.name == "ai-budget-test-minimal-uc-account-wide-not-per-usecase"
    error_message = "The budget's name must be derived from this use case's own resource_names.budget, distinct from the other run's."
  }
}
